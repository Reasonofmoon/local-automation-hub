#Requires AutoHotkey v2.0

class CommandRegistry {
    __New() {
        this.commands := Map()
    }

    Register(id, label, tags, risk, handler) {
        id := Trim(String(id))
        label := Trim(String(label))
        risk := StrLower(Trim(String(risk)))
        if (id = "")
            throw ValueError("Command id cannot be empty")
        if (label = "")
            throw ValueError("Command label cannot be empty")
        if !IsObject(tags)
            throw TypeError("Command tags must be an array")
        if !MapHas(this.commands, id) {
            ; Continue below.
        } else {
            throw Error("Duplicate command id: " id)
        }
        if !IsRisk(risk)
            throw ValueError("Invalid command risk: " risk)
        if !IsObject(handler)
            throw TypeError("Command handler must be callable")

        normalizedTags := []
        for tag in tags {
            tag := Trim(String(tag))
            if (tag != "")
                normalizedTags.Push(tag)
        }
        record := Map(
            "id", id,
            "label", label,
            "tags", normalizedTags,
            "risk", risk,
            "handler", handler
        )
        this.commands[id] := record
        return record
    }

    Search(query) {
        query := StrLower(Trim(String(query)))
        matches := []
        for id, command in this.commands {
            haystack := StrLower(command["label"] " " JoinTags(command["tags"]))
            if (query = "" || InStr(haystack, query))
                matches.Push(command)
        }
        return matches
    }

    Invoke(id, appContext := unset) {
        id := String(id)
        if !MapHas(this.commands, id)
            return Map("success", false, "error", "Unknown command: " id, "id", id)
        try {
            if IsSet(appContext) && IsObject(appContext) && appContext.IsCancelled()
                return Map("success", false, "error", "Command cancelled", "id", id)
            command := this.commands[id]
            if IsSet(appContext)
                return command["handler"].Call(appContext)
            return command["handler"].Call()
        } catch error {
            return Map(
                "success", false,
                "error", SafeErrorMessage(error),
                "id", id
            )
        }
    }

    All() {
        result := []
        for id, command in this.commands
            result.Push(command)
        return result
    }
}

IsRisk(value) {
    return value = "low" || value = "medium" || value = "high"
}

JoinTags(tags) {
    result := ""
    for index, tag in tags
        result .= (index = 1 ? "" : " ") tag
    return result
}

MapHas(map, key) {
    return map.Has(key)
}

SafeErrorMessage(error) {
    try
        return SafeLogger.Redact(error.Message)
    catch
        return "Command failed"
}
