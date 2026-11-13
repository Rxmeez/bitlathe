# release: Homebrew cask for the Direct (Developer ID) build. scripts/release.sh rewrites the version and sha256 lines.
# Publish by copying this file to a tap (e.g. Rxmeez/homebrew-tap, Casks/bitlathe.rb).
cask "bitlathe" do
  version "0.0.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/Rxmeez/bitlathe/releases/download/v#{version}/Bitlathe-#{version}.dmg"
  name "Bitlathe"
  desc "Developer toolbox: format, convert, encode, inspect"
  homepage "https://github.com/Rxmeez/bitlathe"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: ">= :sonoma"

  app "Bitlathe.app"
  binary "#{appdir}/Bitlathe.app/Contents/Helpers/bl"

  zap trash: [
    "~/Library/Application Support/Bitlathe",
    "~/Library/Containers/com.bitlathe.app",
    "~/Library/Preferences/com.bitlathe.app.plist",
  ]
end
