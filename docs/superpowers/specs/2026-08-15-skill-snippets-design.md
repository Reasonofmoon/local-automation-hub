# Skill invocation snippets design

Status: approved design, awaiting written-spec review

## Goal

Replace the two existing local snippets with eighteen fixed slash-command
snippets for the user's most frequently used content and Superpowers workflows.

## Configuration

Only `config/settings.local.ini` changes. The `[Snippets]` section becomes:

```ini
[Snippets]
skill-blog=/blog
skill-k-blog=/k-blog
skill-k-book=/k-book
skill-k-news=/k-news
skill-k-youtube=/k-youtube
skill-research=/research
skill-harness=/harness
skill-notebooklm=/notebooklm
skill-ocr=/ocr
skill-humanizer=/humanizer
skill-brainstorming=/brainstorming
skill-writing-plans=/writing-plans
skill-executing-plans=/executing-plans
skill-subagent-development=/subagent-driven-development
skill-systematic-debugging=/systematic-debugging
skill-tdd=/test-driven-development
skill-verification=/verification-before-completion
skill-using-superpowers=/using-superpowers
```

The existing `student-feedback` and `multiline-prompt` entries are removed.
Other INI sections remain byte-for-byte equivalent in meaning.

## Runtime behavior

Each palette command is exposed as `snippet.<id>`, for example
`snippet.skill-brainstorming`. Invoking it pastes only the slash command into
the previously captured safe input target. It does not submit the command, so
the user can append task-specific instructions and press Enter manually.

## Safety and verification

- Do not add credentials, paths, clipboard contents, or prompt history.
- Preserve all non-Snippet local settings.
- Reload the hub after editing the local INI.
- Verify that all eighteen snippet command IDs are registered through the
  existing configuration path without exercising a real UI or clipboard.

## Out of scope

- Automatic Enter/submission.
- Arguments, variables, menus, aliases, or prompt templates.
- Changes to AHK production modules or tracked example configuration.
