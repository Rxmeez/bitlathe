import Foundation
import BitlatheCore

public struct GitignoreTool: DevTool {
    public static let id = "gitignore.build"
    public static let name = ".gitignore Builder"
    public static let summary = "Compose a .gitignore from built-in templates for languages, frameworks, editors and operating systems"
    public static let category = ToolCategory.generate
    public static let symbol = "eye.slash"
    public static let keywords = ["gitignore", "git", "ignore", "template", "node", "python", "swift", "xcode", "macos", "generate"]
    public static let io = ToolIO(input: .text, output: .text, acceptsFiles: false)
    public static let samples = [ToolSample("Swift app", "swift, xcode, macos, swiftpm"), ToolSample("Web", "node, react, vscode, macos, dotenv"), ToolSample("Python", "python, jupyter, venv, macos")]
    public static let optionFields: [OptionField] = [
        .text("templates", "Templates", placeholder: "node, python, macos (or type in the input)", help: "Comma-separated names; see the list in the output when empty"),
        .toggle("comments", "Section headers", default: true),
    ]
    public struct Options: ToolOptions {
        public var templates = ""
        public var comments = true
        public init() {}
    }
    public init() {}

    public static let templates: [(String, [String], String)] = [
        ("macos", ["mac", "osx"], ".DS_Store\n.AppleDouble\n.LSOverride\nIcon\r\r\n._*\n.DocumentRevisions-V100\n.fseventsd\n.Spotlight-V100\n.TemporaryItems\n.Trashes\n.VolumeIcon.icns\n.com.apple.timemachine.donotpresent\n*.icloud"),
        ("windows", ["win"], "Thumbs.db\nThumbs.db:encryptable\nehthumbs.db\nehthumbs_vista.db\nDesktop.ini\n$RECYCLE.BIN/\n*.lnk\n*.stackdump"),
        ("linux", [], "*~\n.fuse_hidden*\n.directory\n.Trash-*\n.nfs*"),
        ("node", ["npm", "javascript", "js", "typescript", "ts"], "node_modules/\nnpm-debug.log*\nyarn-debug.log*\nyarn-error.log*\npnpm-debug.log*\n.pnpm-store/\n.npm\n.yarn/cache\n.yarn/unplugged\n.yarn/build-state.yml\n.yarn/install-state.gz\n.pnp.*\ndist/\nbuild/\ncoverage/\n*.tsbuildinfo\n.eslintcache\n.stylelintcache\n.parcel-cache\n.turbo\n.cache/"),
        ("react", ["nextjs", "next", "vite"], ".next/\nout/\n.vercel\n.vite/\nstorybook-static/\n*.local"),
        ("vue", ["nuxt"], ".nuxt/\n.output/\n.nitro/\ndist/"),
        ("svelte", ["sveltekit"], ".svelte-kit/\nbuild/"),
        ("angular", [], ".angular/\ndist/\n/connect.lock\n/libpeerconnection.log\ntestem.log\n/typings"),
        ("python", ["py"], "__pycache__/\n*.py[cod]\n*$py.class\n*.so\n.Python\nbuild/\ndevelop-eggs/\ndist/\ndownloads/\neggs/\n.eggs/\nlib/\nlib64/\nparts/\nsdist/\nvar/\nwheels/\n*.egg-info/\n.installed.cfg\n*.egg\npip-log.txt\n.pytest_cache/\n.mypy_cache/\n.ruff_cache/\n.dmypy.json\n.pyre/\n.pytype/\n.coverage\n.coverage.*\nhtmlcov/\n.tox/\n.nox/\n.hypothesis/\n*.cover\ncython_debug/"),
        ("venv", ["virtualenv", "poetry", "uv"], ".venv/\nvenv/\nenv/\nENV/\n.python-version\npoetry.toml\n.uv/"),
        ("jupyter", ["ipynb"], ".ipynb_checkpoints/\nprofile_default/\nipython_config.py"),
        ("django", [], "*.log\nlocal_settings.py\ndb.sqlite3\ndb.sqlite3-journal\nmedia/\nstaticfiles/"),
        ("swift", ["ios"], "*.xcodeproj/*\n!*.xcodeproj/project.pbxproj\n!*.xcodeproj/xcshareddata/\n!*.xcworkspace/contents.xcworkspacedata\n*.xcuserstate\nxcuserdata/\n*.moved-aside\n*.hmap\n*.ipa\n*.dSYM.zip\n*.dSYM\ntimeline.xctimeline\nplayground.xcworkspace\n.build/\nDerivedData/"),
        ("xcode", [], "build/\nDerivedData/\n*.pbxuser\n!default.pbxuser\n*.mode1v3\n!default.mode1v3\n*.mode2v3\n!default.mode2v3\n*.perspectivev3\n!default.perspectivev3\nxcuserdata/\n*.xccheckout\n*.xcscmblueprint\n*.xcresult\n.swiftpm/xcode/package.xcworkspace/xcuserdata/"),
        ("swiftpm", ["spm"], ".build/\n.swiftpm/\nPackage.resolved\n!/Package.resolved\n.index-build/"),
        ("cocoapods", ["pods"], "Pods/\nPodfile.lock\n*.xcworkspace"),
        ("carthage", [], "Carthage/Build/\nCarthage/Checkouts/"),
        ("fastlane", [], "fastlane/report.xml\nfastlane/Preview.html\nfastlane/screenshots/**/*.png\nfastlane/test_output"),
        ("go", ["golang"], "*.exe\n*.exe~\n*.dll\n*.so\n*.dylib\n*.test\n*.out\ngo.work\ngo.work.sum\nvendor/\n/bin/\n/dist/"),
        ("rust", ["cargo"], "target/\ndebug/\n**/*.rs.bk\n*.pdb\nCargo.lock\n!/Cargo.lock"),
        ("java", [], "*.class\n*.log\n*.ctxt\n.mtj.tmp/\n*.jar\n*.war\n*.nar\n*.ear\n*.zip\n*.tar.gz\n*.rar\nhs_err_pid*\nreplay_pid*"),
        ("maven", [], "target/\npom.xml.tag\npom.xml.releaseBackup\npom.xml.versionsBackup\npom.xml.next\nrelease.properties\ndependency-reduced-pom.xml\nbuildNumber.properties\n.mvn/timing.properties\n.mvn/wrapper/maven-wrapper.jar"),
        ("gradle", [], ".gradle/\nbuild/\n!gradle/wrapper/gradle-wrapper.jar\n!**/src/main/**/build/\n!**/src/test/**/build/\n.gradletasknamecache"),
        ("kotlin", [], "*.class\n*.log\n*.ctxt\n.mtj.tmp/\nhs_err_pid*\n.kotlin/"),
        ("android", [], "*.apk\n*.aab\n*.ap_\n*.dex\nbin/\ngen/\nout/\n.gradle/\nlocal.properties\nproguard/\ncaptures/\n.externalNativeBuild\n.cxx/\n*.jks\n*.keystore\ngoogle-services.json"),
        ("flutter", ["dart"], ".dart_tool/\n.flutter-plugins\n.flutter-plugins-dependencies\n.packages\n.pub-cache/\n.pub/\nbuild/\n*.iml\n**/ios/Flutter/.last_build_id\n**/doc/api/"),
        ("csharp", ["dotnet", "c#", ".net"], "bin/\nobj/\n*.user\n*.suo\n*.userosscache\n*.sln.docstates\n[Dd]ebug/\n[Rr]elease/\nx64/\nx86/\n*.pdb\n*.cache\n*.nupkg\n*.snupkg\n.vs/\nTestResults/\n*.VisualState.xml\nproject.lock.json\nartifacts/"),
        ("unity", [], "[Ll]ibrary/\n[Tt]emp/\n[Oo]bj/\n[Bb]uild/\n[Bb]uilds/\n[Ll]ogs/\n[Uu]ser[Ss]ettings/\n[Mm]emoryCaptures/\n*.csproj\n*.unityproj\n*.sln\n*.pidb\n*.booproj\n*.svd\n*.pdb\n*.mdb\n*.opendb\n*.VC.db\nsysinfo.txt\n*.apk\n*.unitypackage\ncrashlytics-build.properties"),
        ("php", ["laravel", "composer"], "/vendor/\ncomposer.phar\n.phpunit.result.cache\n.phpunit.cache/\n/storage/*.key\n/public/hot\n/public/storage\n/bootstrap/cache/*\nHomestead.json\nHomestead.yaml\n.php-cs-fixer.cache"),
        ("ruby", ["rails"], "*.gem\n*.rbc\n/.config\n/coverage/\n/InstalledFiles\n/pkg/\n/spec/reports/\n/spec/examples.txt\n/test/tmp/\n/test/version_tmp/\n/tmp/\n/log/*\n!/log/.keep\n/.bundle\n/vendor/bundle\n/.yardoc\n.byebug_history\n/storage/*\n!/storage/.keep\n/public/assets\n/public/packs\n/node_modules"),
        ("elixir", ["phoenix"], "/_build/\n/cover/\n/deps/\n/doc/\n/.fetch\nerl_crash.dump\n*.ez\n*.beam\n/config/*.secret.exs\n.elixir_ls/"),
        ("c", ["cpp", "c++", "cmake"], "*.o\n*.ko\n*.obj\n*.elf\n*.a\n*.la\n*.lo\n*.so\n*.so.*\n*.dylib\n*.dll\n*.exe\n*.out\n*.app\n*.gch\n*.pch\ncmake-build-*/\nCMakeCache.txt\nCMakeFiles/\nCMakeScripts/\nMakefile\ncmake_install.cmake\ninstall_manifest.txt\ncompile_commands.json\nCTestTestfile.cmake\n_deps/\nbuild/"),
        ("terraform", ["tf"], "**/.terraform/*\n*.tfstate\n*.tfstate.*\ncrash.log\ncrash.*.log\n*.tfvars\n*.tfvars.json\noverride.tf\noverride.tf.json\n*_override.tf\n*_override.tf.json\n.terraformrc\nterraform.rc\n.terraform.lock.hcl"),
        ("docker", [], "docker-compose.override.yml\n.docker/\n*.pid"),
        ("dotenv", ["env", "secrets"], ".env\n.env.*\n!.env.example\n!.env.template\n*.pem\n*.key\n*.p12\n*.pfx\nsecrets.yml\ncredentials.json\nserviceAccountKey.json"),
        ("vscode", ["code"], ".vscode/*\n!.vscode/settings.json\n!.vscode/tasks.json\n!.vscode/launch.json\n!.vscode/extensions.json\n*.code-workspace\n.history/"),
        ("jetbrains", ["intellij", "idea", "pycharm", "webstorm", "goland", "clion", "rider"], ".idea/\n*.iws\n*.iml\n*.ipr\nout/\n.idea_modules/\natlassian-ide-plugin.xml\ncmake-build-*/"),
        ("vim", [], "[._]*.s[a-v][a-z]\n[._]*.sw[a-p]\n[._]s[a-rt-v][a-z]\n[._]ss[a-gi-z]\n[._]sw[a-p]\nSession.vim\nSessionx.vim\n.netrwhist\n*~\ntags\n[._]*.un~"),
        ("emacs", [], "*~\n\\#*\\#\n/.emacs.desktop\n/.emacs.desktop.lock\n*.elc\nauto-save-list\ntramp\n.\\#*\n.org-id-locations\n*_archive\n.projectile\n.dir-locals.el"),
        ("sublime", [], "*.sublime-workspace\n*.sublime-project\nsftp-config.json\nPackage Control.last-run\nPackage Control.ca-list"),
        ("zed", [], ".zed/"),
        ("cursor", ["claude", "ai"], ".cursor/\n.cursorrules\n.claude/settings.local.json\n.aider*\n.continue/"),
        ("logs", [], "logs/\n*.log\nnpm-debug.log*\nyarn-debug.log*\nyarn-error.log*\nlerna-debug.log*\n.pnpm-debug.log*"),
        ("archives", [], "*.7z\n*.dmg\n*.gz\n*.iso\n*.jar\n*.rar\n*.tar\n*.zip"),
        ("sqlite", ["database", "db"], "*.sqlite\n*.sqlite3\n*.sqlite-journal\n*.db\n*.db-shm\n*.db-wal"),
        ("latex", ["tex"], "*.aux\n*.lof\n*.log\n*.lot\n*.fls\n*.out\n*.toc\n*.fmt\n*.fot\n*.cb\n*.cb2\n.*.lb\n*.bbl\n*.bcf\n*.blg\n*.synctex.gz\n*.fdb_latexmk\n*.pdfsync"),
        ("hugo", ["jekyll", "static"], "/public/\n/resources/_gen/\n/assets/jsconfig.json\nhugo_stats.json\n.hugo_build.lock\n_site/\n.sass-cache/\n.jekyll-cache/\n.jekyll-metadata"),
        ("godot", [], ".godot/\n.import/\nexport.cfg\nexport_credentials.cfg\n*.translation\n.mono/\ndata_*/\nmono_crash.*.json"),
        ("firebase", [], ".firebase/\nfirebase-debug.log*\nfirestore-debug.log*\nui-debug.log*\n.firebaserc"),
        ("serverless", ["aws", "sam"], ".serverless/\n.aws-sam/\nsamconfig.toml\n.chalice/deployments/\ncdk.out/\n.cdk.staging/"),
        ("pulumi", [], "Pulumi.*.yaml\n!Pulumi.yaml\n.pulumi/"),
    ]

    public static func resolve(_ name: String) -> (String, String)? {
        let n = name.trimmed().lowercased().removingPrefix(".")
        guard !n.isEmpty else { return nil }
        return templates.first { $0.0 == n || $0.1.contains(n) }.map { ($0.0, $0.2) }
    }

    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        let source = options.templates.isEmpty ? input.text : options.templates
        let names = source.replacingOccurrences(of: "\n", with: ",").split(separator: ",").map { $0.trimmed() }.filter { !$0.isEmpty }
        guard !names.isEmpty else {
            let list = Self.templates.map { $0.0 + ($0.1.isEmpty ? "" : " (\($0.1.joined(separator: ", ")))") }.joined(separator: "\n")
            return ToolOutput(text: "# Available templates — type names separated by commas:\n\n" + list, metadata: [MetaRow("Templates", "\(Self.templates.count)")])
        }
        var out = "# Generated by Bitlathe — \(names.joined(separator: ", "))\n"
        var seen = Set<String>()
        var unknown: [String] = []
        var used: [String] = []
        for n in names {
            guard let (id, body) = Self.resolve(n) else { unknown.append(n); continue }
            if seen.contains(id) { continue }
            seen.insert(id)
            used.append(id)
            if options.comments { out += "\n# ── \(id)\n" }
            for line in body.split(separator: "\n") where !seen.contains("line:" + line) {
                seen.insert("line:" + line)
                out += line + "\n"
            }
        }
        var warnings: [String] = []
        if !unknown.isEmpty { warnings.append("Unknown templates: \(unknown.joined(separator: ", "))") }
        let ruleCount = out.split(separator: "\n").filter { !$0.hasPrefix("#") && !$0.isEmpty }.count
        return ToolOutput(.text(out), language: .properties, metadata: [MetaRow("Templates used", used.joined(separator: ", ")), MetaRow("Rules", "\(ruleCount)")], warnings: warnings, suggestedFileName: "gitignore.txt")
    }
}
