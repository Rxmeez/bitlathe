# release: Homebrew cask for the self-signed build. scripts/ship.sh fills in the version, sha256 and OWNER/REPO, and
# copies the result to Rxmeez/homebrew-tap (Casks/bitlathe.rb). Install with: brew install --cask rxmeez/tap/bitlathe
cask "bitlathe" do
  version "0.0.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/OWNER/REPO/releases/download/v#{version}/Bitlathe-#{version}.zip"
  name "Bitlathe"
  desc "Developer toolbox: paste anything to format, convert, encode or inspect it"
  homepage "https://github.com/OWNER/REPO"

  livecheck do
    url :url
    strategy :github_latest
  end

  # The app updates itself through Sparkle, so brew should not try to.
  auto_updates true
  depends_on macos: ">= :sonoma"

  app "Bitlathe.app"
  binary "#{appdir}/Bitlathe.app/Contents/Helpers/bl"

  uninstall quit: "com.bitlathe.app"

  zap trash: [
    "~/Library/Application Support/Bitlathe",
    "~/Library/Containers/com.bitlathe.app",
    "~/Library/Preferences/com.bitlathe.app.plist",
  ]

  caveats <<~EOS
    Bitlathe is not notarised by Apple, so macOS blocks it the first time
    you open it. Click Done (not Move to Bin), then allow it once:
      System Settings → Privacy & Security → Open Anyway
    Updates install themselves after that, with no more prompts.
    The command line tool is installed as `bl` (try: bl --help).
  EOS
end
