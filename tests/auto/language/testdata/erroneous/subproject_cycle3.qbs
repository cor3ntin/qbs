import qbs 1.0

Project {
    SubProject {
        filePath: "subproject_cycle.qbs"
    }
}

