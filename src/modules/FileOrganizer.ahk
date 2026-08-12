#Requires AutoHotkey v2.0

class FileOrganizer {
    __New(statePath) {
        statePath := Trim(String(statePath))
        if (statePath = "")
            throw ValueError("File organizer state path is required")
        SplitPath(statePath, &stateFileName, &rootDirectory)
        if (rootDirectory = "")
            throw ValueError("File organizer state path must include a root directory")
        this.rootDirectory := NormalizeFileOrganizerPath(rootDirectory)
    }

    BuildPlan(paths, dateStamp) {
        if !(paths is Array)
            throw TypeError("File paths must be an array")
        if !RegExMatch(String(dateStamp), "^\d{4}-\d{2}-\d{2}$")
            throw ValueError("Date stamp must use YYYY-MM-DD")

        year := SubStr(dateStamp, 1, 4)
        month := SubStr(dateStamp, 6, 2)
        destinationDirectory := this.rootDirectory "\" year "\" month
        reservedDestinations := Map()
        plan := []
        for _, rawPath in paths {
            source := NormalizeFileOrganizerPath(rawPath)
            SplitPath(source, &fileName, &sourceDirectory, &extension, &nameWithoutExtension)
            if (fileName = "")
                throw ValueError("File path must name a file")
            destination := this.NextAvailableDestination(destinationDirectory, dateStamp, nameWithoutExtension, extension, reservedDestinations)
            reservedDestinations[StrLower(destination)] := true
            plan.Push({ source: source, destination: destination, status: "pending" })
        }
        return plan
    }

    NextAvailableDestination(destinationDirectory, dateStamp, baseName, extension, reservedDestinations) {
        suffix := 1
        loop {
            collisionSuffix := suffix = 1 ? "" : " (" suffix ")"
            candidate := destinationDirectory "\" dateStamp "_" baseName collisionSuffix (extension = "" ? "" : "." extension)
            if !FileExist(candidate) && !reservedDestinations.Has(StrLower(candidate))
                return candidate
            suffix += 1
        }
    }
}

NormalizeFileOrganizerPath(path) {
    path := Trim(String(path))
    if (path = "")
        throw ValueError("File path cannot be empty")

    requiredLength := DllCall("Kernel32.dll\GetFullPathNameW", "Str", path, "UInt", 0, "Ptr", 0, "Ptr", 0, "UInt")
    if (requiredLength = 0)
        throw OSError(A_LastError, "GetFullPathNameW", path)
    pathBuffer := Buffer((requiredLength + 1) * 2, 0)
    resolvedLength := DllCall("Kernel32.dll\GetFullPathNameW", "Str", path, "UInt", requiredLength + 1, "Ptr", pathBuffer.Ptr, "Ptr", 0, "UInt")
    if (resolvedLength = 0 || resolvedLength > requiredLength)
        throw OSError(A_LastError, "GetFullPathNameW", path)
    return StrGet(pathBuffer, resolvedLength)
}
