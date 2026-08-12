#Requires AutoHotkey v2.0
#Include TestSupport.ahk
#Include ..\src\system\ExplorerSelection.ahk
#Include ..\src\modules\FileOrganizer.ahk

class FakeExplorerSelectionAdapter {
    __New(selectedItems := [], attributes := Map()) {
        this.selectedItems := selectedItems
        this.attributes := attributes
    }

    GetActiveSelectedItems() {
        return this.selectedItems
    }

    GetItemPath(item) {
        return item
    }

    GetAttributes(path) {
        key := StrLower(path)
        return this.attributes.Has(key) ? this.attributes[key] : FileGetAttrib(path)
    }
}

root := CreateTempDirectory()
try {
    sourceDirectory := root "\sources"
    secondSourceDirectory := root "\other-sources"
    folderSelection := root "\folder-selection"
    hiddenSource := sourceDirectory "\hidden.txt"
    systemSource := sourceDirectory "\system.txt"
    source := sourceDirectory "\report.txt"
    duplicateSource := secondSourceDirectory "\report.txt"
    DirCreate(sourceDirectory)
    DirCreate(secondSourceDirectory)
    DirCreate(folderSelection)
    FileAppend("content", source, "UTF-8")
    FileAppend("hidden", hiddenSource, "UTF-8")
    FileAppend("system", systemSource, "UTF-8")
    FileAppend("duplicate", duplicateSource, "UTF-8")

    attributes := Map(
        StrLower(hiddenSource), "H",
        StrLower(systemSource), "S"
    )
    selection := ExplorerSelection(FakeExplorerSelectionAdapter([
        source,
        StrUpper(source),
        folderSelection,
        hiddenSource,
        systemSource
    ], attributes))
    selectedPaths := selection.GetRegularFiles()
    AssertEqual(1, selectedPaths.Length, "filters folders, hidden and system selections")
    AssertEqual(source, selectedPaths[1], "normalizes and deduplicates selected paths")
    AssertThrows(() => ExplorerSelection(FakeExplorerSelectionAdapter()).GetRegularFiles(), "rejects empty Explorer selections")

    organizer := FileOrganizer(root "\state.ini")
    destinationDirectory := root "\2026\08"
    plan := organizer.BuildPlan([source], "2026-08-12")
    AssertEqual(root "\2026\08\2026-08-12_report.txt", plan[1].destination, "builds dated destination")
    AssertEqual(source, plan[1].source, "keeps the source path")
    AssertEqual("pending", plan[1].status, "marks a generated plan pending")
    AssertFalse(DirExist(destinationDirectory), "build plan does not create destination directories")
    AssertTrue(FileExist(source), "build plan does not move the source file")

    DirCreate(destinationDirectory)
    FileAppend("occupied", plan[1].destination, "UTF-8")
    collisionPlan := organizer.BuildPlan([source], "2026-08-12")
    AssertEqual(root "\2026\08\2026-08-12_report (2).txt", collisionPlan[1].destination, "avoids existing destination overwrites")

    multiplePlan := organizer.BuildPlan([source, duplicateSource], "2026-08-13")
    AssertEqual(root "\2026\08\2026-08-13_report.txt", multiplePlan[1].destination, "uses the first available destination")
    AssertEqual(root "\2026\08\2026-08-13_report (2).txt", multiplePlan[2].destination, "avoids collisions within one plan")
    AssertThrows(() => organizer.BuildPlan([source], "2026-8-12"), "requires an ISO date stamp")
} finally {
    DirDelete(root, 1)
}

ExitWithTestResult()

CreateTempDirectory() {
    root := A_Temp "\local-automation-hub-file-organizer-" A_TickCount "-" Random(100000, 999999)
    DirCreate(root)
    return root
}
