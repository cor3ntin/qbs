import qbs
import qbs.File
import qbs.FileInfo
import qbs.ModUtils

Module {
    // JavaScript files which have been "processed" - currently this simply means "copied to output
    // directory" but might later include minification and obfuscation processing
    additionalProductTypes: ["nodejs_processed_js"]

    property path applicationFile
    PropertyOptions {
        name: "applicationFile"
        description: "file whose corresponding output will be executed when running the Node.js app"
    }

    setupRunEnvironment: {
        var v = new ModUtils.EnvironmentVariable("NODE_PATH", qbs.pathListSeparator, qbs.hostOS.contains("windows"));
        // can't use product.buildDirectory here, but RunEnvironment always sets the working
        // directory to the directory containing the target file so we can exploit this for now
        v.prepend(".");
        v.set();
    }

    FileTagger {
        patterns: ["*.js"]
        fileTags: ["js"]
    }

    Rule {
        inputs: ["js"]

        outputArtifacts: {
            var tags = ["nodejs_processed_js"];
            if (input.fileTags.contains("application_js") ||
                product.moduleProperty("nodejs", "applicationFile") === input.filePath)
                tags.push("application");

            return [{
                filePath: product.destinationDirectory + '/' + input.fileName,
                fileTags: tags
            }];
        }

        outputFileTags: ["nodejs_processed_js", "application"]

        prepare: {
            var cmd = new JavaScriptCommand();
            cmd.description = "copying " + FileInfo.fileName(input.filePath);
            cmd.sourceCode = function() {
                File.copy(input.filePath, output.filePath);
            };
            return cmd;
        }
    }
}
