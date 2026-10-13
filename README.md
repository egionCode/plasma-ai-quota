# AI Quota for KDE Plasma 6

A Plasma widget that shows how much of your AI subscription quota is left: the
5-hour and weekly windows of your Claude and Codex (ChatGPT) accounts, and when
each one resets.

## Install

Requires KDE Plasma 6 and Python 3. From a copy of this repository:

```bash
./install.sh
```

Then right-click the desktop or a panel, choose "Add Widgets" and add "AI Quota".
To remove it: `./install.sh --uninstall`.

## Best with clauth

The widget works with a plain Claude Code or Codex login, but for Claude it works
best with [clauth](https://crates.io/crates/clauth) (`cargo install clauth`): it
shows every clauth account at once and keeps the numbers current. Keep
`clauth daemon` running (for example as a systemd user service) so the usage stays
up to date.

## License

MIT. The Claude and OpenAI logos come from [Simple Icons](https://simpleicons.org)
(CC0); the marks belong to their owners.
