// Native floating macOS status panel. No browser, Python, npm or GUI build needed.
ObjC.import("Cocoa");

var app, panel, controller, timer, job;
var titleLabel, detailLabel, countLabel, timeLabel, stageLabel, noteLabel, outputView;
var progress, spinner, retryButton, finishButton, pauseButton, stopButton;
var previousPackage = "", currentDependency = "";
var selfTest = false, ticks = 0;
var lastAppearance = "";
ObjC.bindFunction("kill", ["int", ["int", "int"]]);

function readFile(path) {
    try {
        var value = $.NSString.stringWithContentsOfFileEncodingError($(path), $.NSUTF8StringEncoding, null);
        return value.isNil() ? "" : ObjC.unwrap(value);
    } catch (_) { return ""; }
}

function lines(path) {
    return readFile(path).split(/\r?\n/).filter(function (line) { return line.length > 0; });
}

function logTail() {
    var handle;
    try {
        handle = $.NSFileHandle.fileHandleForReadingAtPath($(job + "/worker.log"));
        if (handle.isNil()) return "";
        var end = Number(handle.seekToEndOfFile);
        handle.seekToFileOffset(Math.max(0, end - 6000));
        var data = handle.readDataToEndOfFile;
        var text;
        // The tail offset may land inside a UTF-8 character. Skip at most the
        // remaining continuation bytes instead of blanking the live output.
        for (var offset = 0; offset < 4; offset++) {
            var part = data.subdataWithRange($.NSMakeRange(offset, Math.max(0, Number(data.length) - offset)));
            text = $.NSString.alloc.initWithDataEncoding(part, $.NSUTF8StringEncoding);
            if (!text.isNil()) break;
            if (Number(data.length) <= offset + 1) break;
        }
        handle.closeFile;
        return text.isNil() ? "" : ObjC.unwrap(text).replace(/\x1b\[[0-9;]*[A-Za-z]/g, "").slice(-2400);
    } catch (_) {
        try { if (handle) handle.closeFile; } catch (ignored) {}
        return "";
    }
}

function label(text, x, y, width, size, bold) {
    var field = $.NSTextField.labelWithString($(text));
    field.frame = $.NSMakeRect(x, y, width, 22);
    field.font = bold ? $.NSFont.boldSystemFontOfSize(size) : $.NSFont.systemFontOfSize(size);
    field.lineBreakMode = $.NSLineBreakByTruncatingMiddle;
    panel.contentView.addSubview(field);
    return field;
}

function button(text, x, action, width) {
    var control = $.NSButton.alloc.initWithFrame($.NSMakeRect(x, 15, width || 128, 30));
    control.title = $(text);
    control.bezelStyle = $.NSBezelStyleRounded;
    control.target = controller;
    control.action = action;
    panel.contentView.addSubview(control);
    return control;
}

function launchRunner(action) {
    var task = $.NSTask.alloc.init;
    task.launchPath = $("/bin/bash");
    var runner = $.NSFileManager.defaultManager.fileExistsAtPath($(job + "/controller.sh")) ? "/controller.sh" : "/runner.sh";
    task.arguments = $([job + runner, action]);
    task.launch;
}

function shellQuote(value) { return "'" + value.replace(/'/g, "'\\''") + "'"; }

function applyAppearance() {
    if (!panel || !outputView || !noteLabel) return;
    var name = ObjC.unwrap(panel.effectiveAppearance.bestMatchFromAppearancesWithNames($([
        $.NSAppearanceNameAqua, $.NSAppearanceNameDarkAqua
    ])));
    if (name === lastAppearance) return;
    lastAppearance = name;
    var dark = name === ObjC.unwrap($.NSAppearanceNameDarkAqua);
    var background = dark ? $.NSColor.colorWithSRGBRedGreenBlueAlpha(0.15, 0.15, 0.16, 1) : $.NSColor.colorWithSRGBRedGreenBlueAlpha(0.94, 0.94, 0.95, 1);
    var text = dark ? $.NSColor.colorWithSRGBRedGreenBlueAlpha(0.94, 0.94, 0.95, 1) : $.NSColor.colorWithSRGBRedGreenBlueAlpha(0.12, 0.12, 0.13, 1);
    panel.contentView.layer.backgroundColor = background.CGColor;
    [titleLabel, detailLabel, countLabel, timeLabel, stageLabel, noteLabel].forEach(function (field) { field.textColor = text; });
    outputView.backgroundColor = dark ? $.NSColor.colorWithSRGBRedGreenBlueAlpha(0.10, 0.10, 0.11, 1) : $.NSColor.whiteColor;
    outputView.textColor = text;
    outputView.enclosingScrollView.backgroundColor = background;
}

function update() {
    applyAppearance();
    var state = readFile(job + "/status").trim() || "pending";
    var pid = Number(readFile(job + "/lock/pid").trim());
    if (state === "running" && (!pid || $.kill(pid, 0) !== 0)) state = "interrupted";
    var current = readFile(job + "/current").trim();
    var queued = lines(job + "/queue");
    var completed = lines(job + "/completed");
    var failed = lines(job + "/failures");
    var active = state === "running" || state === "pending";
    var headings = {
        pending: "Waiting to start", running: "Installing packages",
        interrupted: "Installation interrupted", needs_attention: "Some packages need attention",
        packages_ready: "Packages are ready", cancelled: "Queue abandoned",
        retry_wait: "Waiting to retry unfinished packages", paused: "Queue paused", stopping: "Stopping package queue"
    };
    titleLabel.stringValue = $(headings[state] || state);
    detailLabel.stringValue = $(current ? "Package: " + current : "Homebrew background setup");
    countLabel.stringValue = $(completed.length + " of " + queued.length + " packages completed");
    progress.maxValue = Math.max(queued.length, 1);
    progress.doubleValue = completed.length;
    var started = Number(readFile(job + "/current-started-at").trim());
    var seconds = current && started ? Math.max(0, Math.floor(Date.now() / 1000) - started) : 0;
    timeLabel.stringValue = $(current ? "Current package: " + Math.floor(seconds / 60) + "m " + seconds % 60 + "s" : "Overall progress counts completed packages");
    spinner.hidden = !active;
    if (active) spinner.startAnimation(null); else spinner.stopAnimation(null);
    retryButton.hidden = !(state === "interrupted" || state === "needs_attention" || state === "retry_wait");
    finishButton.hidden = state !== "packages_ready";
    pauseButton.hidden = state === "packages_ready" || state === "cancelled";
    pauseButton.title = $(state === "paused" ? "Resume" : "Pause queue");
    pauseButton.enabled = state !== "stopping";
    stopButton.hidden = state === "packages_ready" || state === "cancelled" || state === "paused";
    stopButton.enabled = state !== "stopping";
    if (state === "packages_ready") {
        noteLabel.stringValue = $("Next: finish shell and Neovim configuration.");
    } else if (state === "stopping") {
        noteLabel.stringValue = $("Stopping this build; completed packages are kept.");
    } else if (state === "retry_wait") {
        var remaining = Math.max(0, Number(readFile(job + "/next-retry").trim()) - Math.floor(Date.now() / 1000));
        noteLabel.stringValue = $(failed.length + " failed • retrying in " + Math.ceil(remaining / 60) + "m • see log for details");
    } else if (state === "paused") {
        noteLabel.stringValue = $("Saved progress is retained. Choose Resume to continue.");
    } else if (state === "needs_attention") {
        noteLabel.stringValue = $(failed.length + " failed package(s). Review the log, then retry.");
    } else if (state === "interrupted") {
        noteLabel.stringValue = $("Completed packages are saved. Retry resumes unfinished work.");
    } else {
        noteLabel.stringValue = $("One package at a time • resumes at login • close window to hide");
    }
    var tail = logTail();
    if (previousPackage !== current) { currentDependency = ""; previousPackage = current; }
    var installEvents = tail.match(/^==> Installing [^\n]+$/gm) || [];
    var basePackage = current.split("/").pop();
    installEvents.forEach(function (event) {
        var dependency = event.match(/^==> Installing (.+) dependency: (.+)$/);
        if (dependency && (dependency[1] === current || dependency[1] === basePackage)) currentDependency = dependency[2];
        if (event === "==> Installing " + current || event === "==> Installing " + basePackage || event.indexOf("==> Installing " + basePackage + " (") === 0) currentDependency = "";
    });
    if (currentDependency && current) detailLabel.stringValue = $("Package: " + current + " • building " + currentDependency);
    var stages = tail.match(/^==> .+$/gm);
    stageLabel.stringValue = $(stages && stages.length ? stages[stages.length - 1].replace(/^==> /, "") : "Build output below");
    var viewport = outputView.enclosingScrollView.contentView.bounds;
    var atBottom = Number(viewport.origin.y) + Number(viewport.size.height) >= Number(outputView.bounds.size.height) - 3;
    if (ObjC.unwrap(outputView.string) !== tail && Number(outputView.selectedRange.length) === 0 && atBottom) {
        outputView.string = $(tail || "Waiting for the package worker…");
        outputView.scrollRangeToVisible($.NSMakeRange(Number(outputView.string.length), 0));
    }
    if (timer && (state === "packages_ready" || state === "cancelled")) timer.invalidate;
}

ObjC.registerSubclass({
    name: "SynologyHomebrewStatusContentView",
    superclass: "NSView",
    methods: {
        "viewDidChangeEffectiveAppearance": { types: ["void", []], implementation: function () { applyAppearance(); } }
    }
});

ObjC.registerSubclass({
    name: "SynologyHomebrewStatusController",
    methods: {
        "tick:": { types: ["void", ["id"]], implementation: function () {
            update();
            if (selfTest && ++ticks === 2) app.terminate(null);
        } },
        "showLog:": { types: ["void", ["id"]], implementation: function () {
            $.NSWorkspace.sharedWorkspace.openURL($.NSURL.fileURLWithPath($(job + "/worker.log")));
        } },
        "retry:": { types: ["void", ["id"]], implementation: function () { launchRunner("resume"); } },
        "pause:": { types: ["void", ["id"]], implementation: function () {
            launchRunner(readFile(job + "/status").trim() === "paused" ? "resume" : "pause");
        } },
        "stop:": { types: ["void", ["id"]], implementation: function () { launchRunner("stop"); } },
        "finish:": { types: ["void", ["id"]], implementation: function () {
            var repo = readFile(job + "/repository").trim();
            if (!repo) return;
            var terminal = Application("Terminal");
            terminal.doScript("cd " + shellQuote(repo) + " && bash ./install-synology-homebrew.sh");
            terminal.activate();
        } },
        "windowWillClose:": { types: ["void", ["id"]], implementation: function () { app.terminate(null); } }
    }
});

function run(argv) {
    if (!argv.length) throw new Error("A package job directory is required.");
    job = argv[0];
    selfTest = argv.indexOf("--self-test") !== -1;
    // A completed job does not reopen its window at every subsequent login.
    var requested = readFile(job + "/show-window").trim() === "yes";
    if (requested) $.NSFileManager.defaultManager.removeItemAtPathError($(job + "/show-window"), null);
    if (!requested && argv.indexOf("--render") === -1 && ["packages_ready", "cancelled"].indexOf(readFile(job + "/status").trim()) !== -1) return;
    app = $.NSApplication.sharedApplication;
    app.setActivationPolicy($.NSApplicationActivationPolicyAccessory);
    controller = $.SynologyHomebrewStatusController.alloc.init;
    panel = $.NSPanel.alloc.initWithContentRectStyleMaskBackingDefer(
        $.NSMakeRect(0, 0, 470, 350),
        $.NSWindowStyleMaskTitled | $.NSWindowStyleMaskClosable | $.NSWindowStyleMaskMiniaturizable | $.NSWindowStyleMaskUtilityWindow,
        $.NSBackingStoreBuffered, false
    );
    panel.title = $("Homebrew package setup");
    if (selfTest && (!panel.miniaturizable || panel.standardWindowButton($.NSWindowMiniaturizeButton).isNil() || !panel.standardWindowButton($.NSWindowMiniaturizeButton).enabled)) {
        throw new Error("Status window must provide its native minimise control.");
    }
    panel.contentView = $.SynologyHomebrewStatusContentView.alloc.initWithFrame($.NSMakeRect(0, 0, 470, 350));
    // Production windows inherit the system appearance. Overrides are for QA only.
    var appearanceIndex = argv.indexOf("--appearance");
    if (appearanceIndex !== -1 && (argv.indexOf("--render") !== -1 || selfTest)) {
        panel.appearance = $.NSAppearance.appearanceNamed(argv[appearanceIndex + 1] === "dark" ? $.NSAppearanceNameDarkAqua : $.NSAppearanceNameAqua);
    }
    panel.contentView.wantsLayer = true;
    panel.level = $.NSFloatingWindowLevel;
    panel.hidesOnDeactivate = false;
    panel.collectionBehavior = $.NSWindowCollectionBehaviorCanJoinAllSpaces | $.NSWindowCollectionBehaviorFullScreenAuxiliary;
    panel.delegate = controller;
    titleLabel = label("Preparing…", 20, 308, 390, 17, true);
    detailLabel = label("", 20, 278, 425, 13, true);
    countLabel = label("", 20, 250, 425, 12, false);
    progress = $.NSProgressIndicator.alloc.initWithFrame($.NSMakeRect(20, 230, 428, 12));
    progress.indeterminate = false;
    progress.minValue = 0;
    panel.contentView.addSubview(progress);
    spinner = $.NSProgressIndicator.alloc.initWithFrame($.NSMakeRect(426, 308, 22, 22));
    spinner.style = $.NSProgressIndicatorStyleSpinning;
    spinner.indeterminate = true;
    panel.contentView.addSubview(spinner);
    timeLabel = label("", 20, 202, 425, 11, false);
    stageLabel = label("", 20, 178, 425, 11, false);
    var scroll = $.NSScrollView.alloc.initWithFrame($.NSMakeRect(20, 83, 428, 89));
    scroll.hasVerticalScroller = true;
    scroll.borderType = $.NSBezelBorder;
    outputView = $.NSTextView.alloc.initWithFrame($.NSMakeRect(0, 0, 408, 89));
    outputView.editable = false;
    outputView.font = $.NSFont.userFixedPitchFontOfSize(10);
    outputView.autoresizingMask = $.NSViewWidthSizable;
    scroll.documentView = outputView;
    panel.contentView.addSubview(scroll);
    noteLabel = label("", 20, 53, 430, 11, false);
    button("Show log", 18, "showLog:", 100);
    pauseButton = button("Pause queue", 128, "pause:", 100);
    stopButton = button("Stop queue", 238, "stop:", 100);
    retryButton = button("Retry now", 348, "retry:", 100);
    finishButton = button("Finish setup…", 318, "finish:");
    update();
    var renderIndex = argv.indexOf("--render");
    if (renderIndex !== -1) {
        panel.contentView.layoutSubtreeIfNeeded;
        var bounds = panel.contentView.bounds;
        var bitmap = panel.contentView.bitmapImageRepForCachingDisplayInRect(bounds);
        panel.contentView.cacheDisplayInRectToBitmapImageRep(bounds, bitmap);
        bitmap.representationUsingTypeProperties($.NSBitmapImageFileTypePNG, $({})).writeToFileAtomically($(argv[renderIndex + 1]), true);
        return "Status window rendered";
    }
    panel.center;
    if (!selfTest) panel.makeKeyAndOrderFront(null);
    timer = $.NSTimer.scheduledTimerWithTimeIntervalTargetSelectorUserInfoRepeats(1, controller, "tick:", null, true);
    app.run;
    return selfTest ? "Status window callbacks verified" : undefined;
}
