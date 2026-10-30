# Prefabs

Your prefabs in the track editor, and a store to share them, as a plugin for the
[Ballest plugin manager](https://github.com/AnythingGoes-ballest/ballest-plugin-manager) (host 0.33.0 or newer).

## In the editor: the prefabs tab

A fifth tab in the editor's left panel, after pieces, details, world settings and the outliner:

- **create from selection**: the selected pieces saved as a new prefab (name, description, up to 3 tags), checked
  against the game's own rules first (2 to 4,096 pieces, never the start pad). **save and publish** puts it on the
  store too.
- Your prefabs in three groups: **local only** (made here, not published), **published by you**, and **downloaded**.
- **place** puts one in front of the camera the way the game's `spawnprefab` does: one group, selected, ready to move.
  With Create Extensions running, it lands where Create Extensions puts new pieces: its placement distance further
  along the view, on whole units (the whole prefab moved by one offset, so its pieces stay where they are to each
  other).
- **more** opens a prefab's page: place it, **replace with the selection** (the old file is kept as a version you can
  put back), edit its name, description and tags, publish it or publish a new version, delete it from this PC or
  from the store.

## The prefab store

Open it from the tab, or **prefabs** in the footer.

- **browse**: everyone's prefabs, most hearted first or newest, by tag, and searched as you type. A heart, and
  **download** (or **get the update**, or **place** for one already here).
- **my prefabs**: what you've published and what is only on this PC; publish, publish an update, delete from the store.
  Your uploads and edits left this hour.

Writing to the store (publishing, editing, hearting, deleting) signs in with Steam first: the game asks Steam for a
ticket made out to this plugin, and the store checks it with Steam. Only a prefab's uploader can change or delete it.

## The practice store

The store is [ballestrecords.com](https://ballestrecords.com/prefabs). Until its routes for the game are live, the
setting **Use ballestrecords.com** is off and the store is a practice copy kept on this PC: thirteen prefabs made by
the site's own Generators (their pictures drawn by the site's renderer), plus whatever you publish to it. It answers
exactly as the site's routes do and keeps their rules (only the uploader changes a prefab; 5 uploads and 60 hearts
and edits an hour, counted per session here), so every flow can be tried. Nothing in it leaves this PC.

With the setting on, browsing and downloading use the site; publishing, editing, hearting and deleting say they aren't
on the site yet, and pictures show as "no picture yet" until the host can save a download to a file.

## Files

- `main.as`: settings, the store's cards, store actions (signed in first, signed in again once on a 401)
- `server.as`: the store's calls, to the site or the practice copy; `fakestore.as`: the practice copy
- `library.as`: the prefabs on this PC (the game's Prefabs folder) and what is known of them
- `place.as`: placing a prefab; `tab.as`: the editor tab; `store.as`: the store window; `util.as`: text helpers
- `data/store`, `data/store.txt`: the practice store's prefabs and their details

## License

MIT
