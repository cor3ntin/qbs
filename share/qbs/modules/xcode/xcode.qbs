import qbs
import qbs.BundleTools
import qbs.File
import qbs.FileInfo
import qbs.DarwinTools
import qbs.ModUtils
import qbs.PropertyList
import 'xcode.js' as Utils

Module {
    condition: qbs.hostOS.contains("darwin") && qbs.targetOS.contains("darwin") &&
               qbs.toolchain.contains("xcode")

    property path developerPath: "/Applications/Xcode.app/Contents/Developer"
    property string sdk: DarwinTools.applePlatformName(qbs.targetOS)
    property stringList targetDevices: DarwinTools.targetDevices(qbs.targetOS)

    readonly property string sdkName: {
        if (_sdkSettings) {
            return _sdkSettings["CanonicalName"];
        }
    }

    readonly property string sdkVersion: {
        if (_sdkSettings) {
            return _sdkSettings["Version"];
        }
    }

    readonly property string latestSdkName: {
        if (_availableSdks) {
            return _availableSdks[_availableSdks.length - 1]["CanonicalName"];
        }
    }

    readonly property string latestSdkVersion: {
        if (_availableSdks) {
            return _availableSdks[_availableSdks.length - 1]["Version"];
        }
    }

    readonly property stringList availableSdkNames: {
        if (_availableSdks) {
            return _availableSdks.map(function (obj) { return obj["CanonicalName"]; });
        }
    }

    readonly property stringList availableSdkVersions: {
        if (_availableSdks) {
            return _availableSdks.map(function (obj) { return obj["Version"]; });
        }
    }

    property string signingIdentity
    readonly property string actualSigningIdentity: {
        if (_actualSigningIdentity && _actualSigningIdentity.length === 1)
            return _actualSigningIdentity[0][0];
    }

    readonly property string actualSigningIdentityDisplayName: {
        if (_actualSigningIdentity && _actualSigningIdentity.length === 1)
            return _actualSigningIdentity[0][1];
    }

    property path signingEntitlements

    property string provisioningProfile
    property path provisioningProfilePath: {
        var files = _availableProvisioningProfiles;
        for (var i in files) {
            var data = Utils.readProvisioningProfileData(files[i]);
            if (data["UUID"] === provisioningProfile ||
                data["Name"] === provisioningProfile) {
                return files[i];
            }
        }
    }

    property string securityName: "security"
    property string securityPath: securityName

    property string codesignName: "codesign"
    property string codesignPath: codesignName
    property stringList codesignFlags

    readonly property path toolchainPath: FileInfo.joinPaths(toolchainsPath,
                                                             "XcodeDefault" + ".xctoolchain")
    readonly property path platformPath: FileInfo.joinPaths(platformsPath,
                                                            Utils.applePlatformDirectoryName(
                                                                qbs.targetOS)
                                                            + ".platform")
    readonly property path sdkPath: FileInfo.joinPaths(sdksPath,
                                                       Utils.applePlatformDirectoryName(
                                                           qbs.targetOS, sdkVersion)
                                                       + ".sdk")

    // private properties
    readonly property path toolchainsPath: FileInfo.joinPaths(developerPath, "Toolchains")
    readonly property path platformsPath: FileInfo.joinPaths(developerPath, "Platforms")
    readonly property path sdksPath: FileInfo.joinPaths(platformPath, "Developer", "SDKs")

    readonly property path platformInfoPlist: FileInfo.joinPaths(platformPath, "Info.plist")
    readonly property path sdkSettingsPlist: FileInfo.joinPaths(sdkPath, "SDKSettings.plist")
    readonly property path toolchainInfoPlist: FileInfo.joinPaths(toolchainPath,
                                                                  "ToolchainInfo.plist")

    readonly property stringList _actualSigningIdentity: {
        if (/^[A-Fa-f0-9]{40}$/.test(signingIdentity)) {
            return signingIdentity;
        }

        var identities = Utils.findSigningIdentities(securityPath, signingIdentity);
        if (identities && identities.length > 1) {
            throw "Signing identity '" + signingIdentity + "' is ambiguous";
        }

        return identities;
    }

    property path provisioningProfilesPath: {
        return FileInfo.joinPaths(qbs.getEnv("HOME"), "Library/MobileDevice/Provisioning Profiles");
    }

    readonly property var _availableSdks: Utils.sdkInfoList(sdksPath)

    readonly property var _sdkSettings: {
        if (_availableSdks) {
            for (var i in _availableSdks) {
                if (_availableSdks[i]["Version"] === sdk)
                    return _availableSdks[i];
                if (_availableSdks[i]["CanonicalName"] === sdk)
                    return _availableSdks[i];
            }

            // Latest SDK available for the platform
            if (DarwinTools.applePlatformName(qbs.targetOS) === sdk)
                return _availableSdks[_availableSdks.length - 1];
        }
    }

    readonly property pathList _availableProvisioningProfiles: {
        var profiles = File.directoryEntries(provisioningProfilesPath,
                                             File.Files | File.NoDotAndDotDot);
        return profiles.map(function (s) {
            return FileInfo.joinPaths(provisioningProfilesPath, s);
        }).filter(function (s) {
            return s.endsWith(".mobileprovision") || s.endsWith(".provisionprofile");
        });
    }

    qbs.sysroot: sdkPath

    validate: {
        if (!_availableSdks) {
            throw "There are no SDKs available for this platform in the Xcode installation.";
        }

        if (!_sdkSettings) {
            throw "There is no matching SDK available for ' + sdk + '.";
        }

        var validator = new ModUtils.PropertyValidator("xcode");
        validator.setRequiredProperty("developerPath", developerPath);
        validator.setRequiredProperty("sdk", sdk);
        validator.setRequiredProperty("sdkName", sdkName);
        validator.setRequiredProperty("sdkVersion", sdkVersion);
        validator.setRequiredProperty("toolchainsPath", toolchainsPath);
        validator.setRequiredProperty("toolchainPath", toolchainPath);
        validator.setRequiredProperty("platformsPath", platformsPath);
        validator.setRequiredProperty("platformPath", platformPath);
        validator.setRequiredProperty("sdksPath", sdkPath);
        validator.setRequiredProperty("sdkPath", sdkPath);
        validator.addVersionValidator("sdkVersion", sdkVersion, 2, 2);
        validator.addCustomValidator("sdkName", sdkName, function (value) {
            return value === Utils.applePlatformDirectoryName(
                        qbs.targetOS, sdkVersion, false).toLowerCase();
        }, " is '" + sdkName + "', but target OS is [" + qbs.targetOS.join(",")
        + "] and Xcode SDK version is '" + sdkVersion + "'");
        validator.validate();
    }

    property var buildEnv: {
        var env = {
            "DEVELOPER_DIR": developerPath,
            "SDKROOT": sdkPath
        };

        var prefixes = [platformPath + "/Developer", toolchainPath, developerPath];
        for (var i = 0; i < prefixes.length; ++i) {
            var codesign_allocate = prefixes[i] + "/usr/bin/codesign_allocate";
            if (File.exists(codesign_allocate)) {
                env["CODESIGN_ALLOCATE"] = codesign_allocate;
                break;
            }
        }

        return env;
    }

    setupBuildEnvironment: {
        var v = new ModUtils.EnvironmentVariable("PATH", qbs.pathListSeparator, false);
        v.prepend(platformPath + "/Developer/usr/bin");
        v.prepend(developerPath + "/usr/bin");
        v.set();

        for (var key in buildEnv) {
            v = new ModUtils.EnvironmentVariable(key);
            v.value = buildEnv[key];
            v.set();
        }
    }

    Group {
        name: "Provisioning Profile"
        files: xcode.provisioningProfilePath
            ? [xcode.provisioningProfilePath]
            : []
    }

    FileTagger {
        fileTags: ["xcode.provisioningprofile"]
        patterns: ["*.mobileprovision", "*.provisionprofile"]
    }

    Rule {
        multiplex: true
        inputs: ["xcode.provisioningprofile"]

        Artifact {
            filePath: FileInfo.joinPaths(product.destinationDirectory,
                                         product.targetName + ".xcent")
            fileTags: ["xcent"]
        }

        prepare: {
            var cmd = new JavaScriptCommand();
            cmd.description = "generating entitlements";
            cmd.highlight = "codegen";
            cmd.bundleIdentifier = product.moduleProperty("bundle", "identifier");
            cmd.signingEntitlements = ModUtils.moduleProperty(product, "signingEntitlements");
            cmd.platformPath = ModUtils.moduleProperty(product, "platformPath");
            cmd.sdkPath = ModUtils.moduleProperty(product, "sdkPath");
            cmd.sourceCode = function() {
                var provData = Utils.readProvisioningProfileData(
                            inputs["xcode.provisioningprofile"][0].filePath);

                var aggregateEntitlements = {};

                // Start building up an aggregate entitlements plist from the files in the SDKs,
                // which contain placeholders in the same manner as Info.plist
                function entitlementsFileContents(path) {
                    return File.exists(path) ? BundleTools.infoPlistContents(path) : undefined;
                }
                var entitlementsSources = [
                    entitlementsFileContents(FileInfo.joinPaths(platformPath, "Entitlements.plist")),
                    entitlementsFileContents(FileInfo.joinPaths(sdkPath, "Entitlements.plist")),
                    entitlementsFileContents(signingEntitlements)
                ];

                for (var i = 0; i < entitlementsSources.length; ++i) {
                    var contents = entitlementsSources[i];
                    for (var key in contents) {
                        if (contents.hasOwnProperty(key))
                            aggregateEntitlements[key] = contents[key];
                    }
                }

                contents = provData["Entitlements"];
                for (key in contents) {
                    if (contents.hasOwnProperty(key) && !aggregateEntitlements.hasOwnProperty(key))
                        aggregateEntitlements[key] = contents[key];
                }

                // Expand entitlements variables with data from the provisioning profile
                var env = {
                    "AppIdentifierPrefix": provData["ApplicationIdentifierPrefix"] + ".",
                    "CFBundleIdentifier": bundleIdentifier
                };
                DarwinTools.expandPlistEnvironmentVariables(aggregateEntitlements, env, true);

                // Anything with an undefined or otherwise empty value should be removed
                // Only JSON-formatted plists can have null values, other formats error out
                // This also follows Xcode behavior
                DarwinTools.cleanPropertyList(aggregateEntitlements);

                var plist = new PropertyList();
                try {
                    plist.readFromObject(aggregateEntitlements);
                    plist.writeToFile(outputs.xcent[0].filePath, "xml1");
                } finally {
                    plist.clear();
                }
            };
            return [cmd];
        }
    }
}
