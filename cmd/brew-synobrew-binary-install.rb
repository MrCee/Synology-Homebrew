# frozen_string_literal: true

# Process-local build refusal. Never modifies Homebrew's installed sources.
# Homebrew has no public strict bottle-only install switch; --force-bottle alone
# can still build. Keep the dependency installer under the same guard.
require "formula_installer"
require "cmd/install"

if ARGV.any? { |arg| arg.split("/").last.to_s.match?(/\A(?:avast|xournal)/i) }
  abort "Installation permanently blocked by user policy: Avast and Xournal++."
end

unless HOMEBREW_VERSION.start_with?("7.0.") &&
       FormulaInstaller.instance_method(:build).arity.zero? &&
       FormulaInstaller.instance_methods.include?(:prelude_fetch)
  abort "Unsupported Homebrew internals; refusing installation until the binary guard is reviewed."
end

module SynobrewBinaryOnly
  def prelude_fetch(**options)
    unless pour_bottle?
      if (report = ENV["SYNOBREW_SOURCE_REQUIRED_FILE"])
        File.write(report, formula.full_name)
      end
      raise "Binary-only: no usable bottle for #{formula.full_name}; source build refused."
    end

    super
  end

  def build
    raise "Binary-only: source build refused for #{formula.full_name}."
  end
end

FormulaInstaller.prepend(SynobrewBinaryOnly)

if ARGV == ["--guard-self-test"]
  probe = FormulaInstaller.allocate
  def probe.formula = Struct.new(:full_name).new("guard-test")
  def probe.pour_bottle? = false
  [:build, :prelude_fetch].each do |method|
    begin
      probe.public_send(method)
    rescue RuntimeError => e
      raise unless e.message.start_with?("Binary-only:")

      puts "PASS: #{method} refuses source compilation"
      next
    end
    abort "FAIL: #{method} did not refuse compilation"
  end
  exit 0
end

%w[HOMEBREW_NO_AUTO_UPDATE HOMEBREW_NO_INSTALL_CLEANUP
   HOMEBREW_NO_INSTALL_UPGRADE HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK
   HOMEBREW_NO_ASK].each { |name| ENV[name] = "1" }
Homebrew::API.fetch_api_files!
Homebrew::Cmd::InstallCmd.new(["--formula", *ARGV].freeze).run
