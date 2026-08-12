#Requires AutoHotkey v2.0

class HubConfig {
    static Load(path) {
        path := String(path)
        if !FileExist(path)
            throw OSError("Configuration file not found: " path)

        config := Map(
            "General", Map(),
            "KakaoAccounts", Map(),
            "Snippets", Map(),
            "Workspace", Map()
        )
        raw := FileRead(path, "UTF-8")
        currentSection := ""
        for line in StrSplit(raw, "`n", "`r") {
            line := Trim(line, " `t")
            if (line = "" || SubStr(line, 1, 1) = ";" || SubStr(line, 1, 1) = "#")
                continue
            if (SubStr(line, 1, 1) = "[" && SubStr(line, -1) = "]") {
                currentSection := Trim(SubStr(line, 2, StrLen(line) - 2))
                continue
            }
            equalsAt := InStr(line, "=")
            if (!equalsAt || currentSection = "")
                continue
            key := Trim(SubStr(line, 1, equalsAt - 1))
            value := Trim(SubStr(line, equalsAt + 1))
            if (key = "")
                continue
            value := DecodeConfigValue(value)

            if (currentSection = "General") {
                config["General"][key] := value
            } else if (currentSection = "KakaoAccounts") {
                if IsSensitiveKakaoAccountKey(key)
                    throw ValueError("KakaoAccounts key cannot contain credential data: " key)
                if !IsKakaoCredentialTarget(value)
                    throw ValueError("KakaoAccounts target must be a credential reference: " key)
                config["KakaoAccounts"][key] := value
            } else if (currentSection = "Snippets") {
                config["Snippets"][key] := value
            } else if (SubStr(currentSection, 1, 10) = "Workspace.") {
                modeId := SubStr(currentSection, 11)
                if !config["Workspace"].Has(modeId)
                    config["Workspace"][modeId] := Map()
                if (key = "Items")
                    config["Workspace"][modeId][key] := ParseWorkspaceItems(value)
                else
                    config["Workspace"][modeId][key] := value
            }
        }

        ; Use IniRead for the well-known General values so malformed INI data is
        ; surfaced by the same Windows parser used by the application.
        general := config["General"]
        iniKakaoPath := IniRead(path, "General", "KakaoPath", "")
        iniLogLevel := IniRead(path, "General", "LogLevel", "")
        if (iniKakaoPath != "")
            general["KakaoPath"] := DecodeConfigValue(iniKakaoPath)
        if (iniLogLevel != "")
            general["LogLevel"] := DecodeConfigValue(iniLogLevel)

        config["__sourcePath"] := path
        return config
    }

    static Validate(config) {
        errors := []
        if !IsObject(config) {
            errors.Push("Configuration must be a map")
            return errors
        }
        for section in ["General", "KakaoAccounts", "Snippets", "Workspace"] {
            if !config.Has(section) || !IsObject(config[section])
                errors.Push("Missing section: " section)
        }
        if !config.Has("General") || !IsObject(config["General"]) {
            return errors
        }
        general := config["General"]
        if !general.Has("KakaoPath") || Trim(String(general["KakaoPath"])) = ""
            errors.Push("General.KakaoPath is required")
        if general.Has("LogLevel") {
            level := StrLower(Trim(String(general["LogLevel"])))
            if !(level = "debug" || level = "info" || level = "warn" || level = "error")
                errors.Push("General.LogLevel must be debug, info, warn, or error")
        }
        if config.Has("KakaoAccounts") && IsObject(config["KakaoAccounts"]) {
            for alias, target in config["KakaoAccounts"] {
                if (Trim(String(alias)) = "" || Trim(String(target)) = "")
                    errors.Push("KakaoAccounts entries require alias and target: " alias)
                if IsSensitiveKakaoAccountKey(alias)
                    errors.Push("KakaoAccounts key cannot contain credential data: " alias)
                if !IsKakaoCredentialTarget(target)
                    errors.Push("KakaoAccounts target must be a credential reference: " alias)
            }
        }
        if config.Has("Snippets") && IsObject(config["Snippets"]) {
            for id, body in config["Snippets"] {
                if (Trim(String(id)) = "")
                    errors.Push("Snippet id cannot be empty")
                if IsObject(body)
                    errors.Push("Snippet body must be text: " id)
            }
        }
        if config.Has("Workspace") && IsObject(config["Workspace"]) {
            for modeId, mode in config["Workspace"] {
                if !IsObject(mode) {
                    errors.Push("Workspace mode must be a map: " modeId)
                    continue
                }
                if !mode.Has("Items") || !IsObject(mode["Items"]) {
                    errors.Push("Workspace." modeId ".Items must be a list")
                    continue
                }
                for item in mode["Items"] {
                    if !RegExMatch(String(item), "i)^(app|folder|url)\|.+$")
                        errors.Push("Workspace." modeId " has invalid item: " item)
                }
            }
        }
        CheckUnexpanded(config, errors, "")
        return errors
    }
}

IsSensitiveKakaoAccountKey(key) {
    normalizedKey := StrLower(Trim(String(key)))
    return RegExMatch(normalizedKey, "i)(password|secret|credential_?blob|credential)")
}

IsKakaoCredentialTarget(target) {
    return RegExMatch(Trim(String(target)), "^LocalAutomationHub/Kakao/[A-Za-z0-9._-]+$")
}

ParseWorkspaceItems(value) {
    items := []
    for _, item in StrSplit(value, ";") {
        item := Trim(item)
        if (item != "")
            items.Push(item)
    }
    return items
}

DecodeConfigValue(value) {
    value := ExpandEnvironmentPlaceholders(String(value))
    marker := "__LOCAL_AUTOMATION_HUB_BACKSLASH__"
    value := StrReplace(value, "\\", marker)
    value := StrReplace(value, "\n", "`n")
    return StrReplace(value, marker, "\")
}

ExpandEnvironmentPlaceholders(value) {
    offset := 1
    while (match := RegExMatch(value, "%([^%]+)%", &found, offset)) {
        name := found[1]
        replacement := EnvGet(name)
        if (replacement = "")
            replacement := "%" name "%"
        value := SubStr(value, 1, match - 1) replacement SubStr(value, match + StrLen(found[0]))
        offset := match + StrLen(replacement)
    }
    return value
}

CheckUnexpanded(value, errors, path) {
    if IsObject(value) {
        if (value is Array) {
            for index, child in value
                CheckUnexpanded(child, errors, path "[" index "]")
        } else {
            for key, child in value {
                if (String(key) = "__sourcePath")
                    continue
                CheckUnexpanded(child, errors, path = "" ? String(key) : path "." key)
            }
        }
        return
    }
    if RegExMatch(String(value), "%[^%]+%")
        errors.Push("Unresolved environment placeholder at " path)
}
