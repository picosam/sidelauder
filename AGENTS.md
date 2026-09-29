# Sidelauder: instructions for agents

Sidelauder is a macOS rail that switches between the Claude Desktop profiles
created by claude-multiprofile. The plan is [docs/spec.md](docs/spec.md);
read its §2.3 (invariants) and §7.0 (foundation rule) before changing code.
`CLAUDE.md` is a symlink to this file.

## Public tree

This repository is public. No fact about a contributor's Mac, accounts,
profile names, or paths under a real home directory enters it. Spike reports
call profiles A, B and C and keep raw logs outside the tree.

Before committing, `git config user.email` must print the maintainer's
address from this clone's local config. Never commit under another identity.

## Review

Reviews run through loupe. [review.toml](review.toml) declares the roles
(author and reviewer), the gates and the taxonomy; read them there, not here.

- Review is the default end of an implementation session
  (`review_default = "on"`). The author runs `loupe handoff` unasked when the
  work is done, unless the person declined a review that session. Both sides
  follow the installed loupe adapter and stop where it says stop.
- Outside a granted window a person carries each envelope between author and
  reviewer, and no agent invokes the other side of a round.

Agent-relayed review windows are declared here by name. A window is the operator's decision, granted per lineage, bounded in rounds, and recorded by the harness that carries it. Inside a granted window that harness hands the open request's relay block to the reviewer whole and unedited, and the request's Roles line names the harness as `relay=` instead of a person. No agent grants or extends a window, and no agent edits what the reviewer is handed. The author's side never writes, edits or substitutes the reviewer's verdict; the stamped reviewer writes and validates its own verdict, exactly as the adapter's procedure requires, and stops there. Outside a granted window the relay is a person's.

## Merging

- Work happens on the agreed branch, in logical-unit commits. Nothing is
  committed to `main` directly.
- Nothing is pushed except by `loupe handoff`, which commits and pushes the
  reviewed branch, or on the maintainer's explicit request. Pushing `main`,
  tags and any history rewrite need the maintainer's word each time.
- The maintainer (GitHub `picosam`) approves reviewed work by merging its pull
  request after a clean loupe verdict on the exact reviewed commit.
- Nothing on GitHub enforces that approval: `main` has no branch protection
  and no required review (`enforcement = "none"` in review.toml). It is a
  rule agents follow, not a gate the platform checks.

## Generated files

None yet. When one is added, it is named here with the command that
regenerates it, and it is regenerated, never edited by hand.

## Talking to the maintainer

Speak in plain language. When a project key, enum value or status code
appears in prose, give its plain meaning beside it on first use in that
reply. Identifiers keep their exact form inside artifacts.
