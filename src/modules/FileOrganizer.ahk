#Requires AutoHotkey v2.0

class FileOrganizer {
    __New(statePath) {
        statePath := Trim(String(statePath))
        if (statePath = "")
            throw ValueError("File organizer state path is required")
        SplitPath(statePath, &stateFileName, &rootDirectory)
        if (rootDirectory = "")
            throw ValueError("File organizer state path must include a root directory")
        this.statePath := NormalizeFileOrganizerPath(statePath)
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

    ApplyPlan(plan, confirmer) {
        this.RequireConfirmer(confirmer)
        normalizedPlan := this.NormalizePlan(plan)
        preview := this.BuildPreview(normalizedPlan, "Move selected files")
        if !confirmer.Call(preview)
            return this.NewResult(true)

        try {
            this.ValidatePlanForMutation(normalizedPlan)
        } catch as validationFailure {
            result := this.NewResult(true)
            result.failed.Push({ source: "", destination: "", error: validationFailure.Message })
            return result
        }
        result := this.NewResult(false)
        for _, item in normalizedPlan {
            try {
                SplitPath(item.destination, , &destinationDirectory)
                DirCreate(destinationDirectory)
                FileMove(item.source, item.destination, 0)
                result.succeeded.Push({ source: item.source, destination: item.destination })
            } catch as moveFailure {
                result.failed.Push({ source: item.source, destination: item.destination, error: moveFailure.Message })
            }
        }
        if (result.succeeded.Length > 0)
            this.PersistState(result.succeeded)
        return result
    }

    UndoLast(confirmer) {
        this.RequireConfirmer(confirmer)
        storedMoves := this.LoadState()
        reversePlan := []
        for _, move in storedMoves
            reversePlan.Push({ source: move.destination, destination: move.source })
        preview := this.BuildPreview(reversePlan, "Undo last file move")
        if !confirmer.Call(preview)
            return this.NewResult(true)

        try {
            this.ValidatePlanForMutation(reversePlan)
        } catch as validationFailure {
            result := this.NewResult(true)
            result.failed.Push({ source: "", destination: "", error: validationFailure.Message })
            return result
        }
        result := this.NewResult(false)
        pendingMoves := []
        for index, item in reversePlan {
            try {
                SplitPath(item.destination, , &destinationDirectory)
                DirCreate(destinationDirectory)
                FileMove(item.source, item.destination, 0)
                result.succeeded.Push({ source: item.source, destination: item.destination })
            } catch as moveFailure {
                result.failed.Push({ source: item.source, destination: item.destination, error: moveFailure.Message })
                pendingMoves.Push(storedMoves[index])
            }
        }
        if (pendingMoves.Length = 0) {
            FileDelete(this.statePath)
        } else {
            this.PersistState(pendingMoves)
        }
        return result
    }

    RequireConfirmer(confirmer) {
        if !IsObject(confirmer) || !HasMethod(confirmer, "Call")
            throw TypeError("File organizer confirmer must be callable")
    }

    NormalizePlan(plan) {
        if !(plan is Array) || (plan.Length = 0)
            throw ValueError("File organizer plan must contain at least one file")
        normalizedPlan := []
        for _, rawItem in plan {
            if !IsObject(rawItem) || !rawItem.HasOwnProp("source") || !rawItem.HasOwnProp("destination")
                throw TypeError("File organizer plan items require source and destination paths")
            normalizedPlan.Push({
                source: NormalizeFileOrganizerPath(rawItem.source),
                destination: NormalizeFileOrganizerPath(rawItem.destination)
            })
        }
        return normalizedPlan
    }

    ValidatePlanForMutation(plan) {
        destinations := Map()
        for _, item in plan {
            if !FileExist(item.source) || InStr(FileGetAttrib(item.source), "D")
                throw Error("File move plan changed: source is unavailable: " item.source)
            if FileExist(item.destination)
                throw Error("File move plan changed: destination is occupied: " item.destination)
            destinationKey := StrLower(item.destination)
            if destinations.Has(destinationKey)
                throw Error("File move plan contains duplicate destinations")
            destinations[destinationKey] := true
        }
    }

    BuildPreview(plan, title) {
        preview := title ":`n"
        for _, item in plan
            preview .= item.source "`n  -> " item.destination "`n"
        return RTrim(preview, "`n")
    }

    NewResult(aborted) {
        return { succeeded: [], failed: [], aborted: aborted }
    }

    PersistState(moves) {
        stateDirectory := ""
        SplitPath(this.statePath, , &stateDirectory)
        DirCreate(stateDirectory)
        temporaryPath := this.statePath ".tmp"
        if FileExist(temporaryPath)
            FileDelete(temporaryPath)
        stateFile := FileOpen(temporaryPath, "w", "UTF-8-RAW")
        try {
            stateFile.Write("version=1`ncount=" moves.Length "`n")
            for index, move in moves {
                stateFile.Write("source" index "=" FileOrganizerEncodePath(move.source) "`n")
                stateFile.Write("destination" index "=" FileOrganizerEncodePath(move.destination) "`n")
            }
        } finally {
            stateFile.Close()
        }
        FileMove(temporaryPath, this.statePath, 1)
    }

    LoadState() {
        if !FileExist(this.statePath)
            throw Error("No file move is available to undo")
        stateFile := FileOpen(this.statePath, "r", "UTF-8-RAW")
        try {
            lines := StrSplit(stateFile.Read(), "`n", "`r")
        } finally {
            stateFile.Close()
        }
        if (lines.Length < 2) || (lines[1] != "version=1") || !RegExMatch(lines[2], "^count=(\d+)$", &countMatch)
            throw Error("File undo state is invalid")
        count := Integer(countMatch[1])
        if (count < 1) || (lines.Length < (count * 2) + 2)
            throw Error("File undo state is invalid")
        moves := []
        Loop count {
            index := A_Index
            sourcePrefix := "source" index "="
            destinationPrefix := "destination" index "="
            sourceLine := lines[(index * 2) + 1]
            destinationLine := lines[(index * 2) + 2]
            if !InStr(sourceLine, sourcePrefix) = 1 || !InStr(destinationLine, destinationPrefix) = 1
                throw Error("File undo state is invalid")
            moves.Push({
                source: FileOrganizerDecodePath(SubStr(sourceLine, StrLen(sourcePrefix) + 1)),
                destination: FileOrganizerDecodePath(SubStr(destinationLine, StrLen(destinationPrefix) + 1))
            })
        }
        return moves
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

FileOrganizerEncodePath(path) {
    path := NormalizeFileOrganizerPath(path)
    encoded := ""
    loop StrLen(path)
        encoded .= Format("{:04X}", NumGet(StrPtr(path), (A_Index - 1) * 2, "UShort"))
    return encoded
}

FileOrganizerDecodePath(encoded) {
    if !RegExMatch(encoded, "i)^(?:[0-9a-f]{4})+$")
        throw Error("File undo state is invalid")
    characterCount := StrLen(encoded) // 4
    pathBuffer := Buffer((characterCount + 1) * 2, 0)
    loop characterCount
        NumPut("UShort", Integer("0x" SubStr(encoded, ((A_Index - 1) * 4) + 1, 4)), pathBuffer, (A_Index - 1) * 2)
    return NormalizeFileOrganizerPath(StrGet(pathBuffer, characterCount))
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
