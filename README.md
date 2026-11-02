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
  from the store. A prefab downloaded from someone else is only placed, updated from the store or deleted from this PC:
  replacing and editing are for your own.

## The prefab store

Open it from the tab, or **prefabs** in the footer.

- **browse**: everyone's prefabs, most hearted first or newest, by tag, and searched as you type. A heart, and
  **download** (or **get the update**, or **place** for one already here).
- **my prefabs**: what you've published and what is only on this PC; publish, publish an update, delete from the store.
  Your uploads and edits left this hour.

Writing to the store (publishing, editing, hearting, deleting) signs in with Steam first: the game asks Steam for a
ticket made out to this plugin, and the store checks it with Steam. Only a prefab's uploader can change or delete it.

## The practice store

The store is [ballestrecords.com](https://ballestrecords.com/prefabs) (the setting **Use ballestrecords.com**, on by
default). The site keeps a prefab's file as it was uploaded, so a published prefab changed here is published as a new
one there; its name, description and tags can be edited. Pictures come from the site's thumbnail route, saved in the
plugin's cache (`PluginManager\cache\prefabs`) once per edit. The site's list is the same for everyone, so the hearts
shown as yours are the ones given from this PC.

With the setting off, the store is a practice copy kept on this PC: thirteen prefabs made by the site's own Generators
(their pictures drawn by the site's renderer), plus whatever you publish to it. It answers exactly as the site's routes
do and keeps their rules (only the uploader changes a prefab; 5 uploads and 60 hearts and edits an hour, counted per
session here), and takes new versions of a file, so every flow can be tried. Nothing in it leaves this PC.

## Files

- `main.as`: settings, the store's cards, store actions (signed in first, signed in again once on a 401)
- `server.as`: the store's calls, to the site or the practice copy; `fakestore.as`: the practice copy
- `library.as`: the prefabs on this PC (the game's Prefabs folder) and what is known of them
- `thumbs.as`: the site's pictures, saved to files, and the hearts given from this PC; own prefabs get a picture of the
  editor's view from their page (Screen::Capture)
- `place.as`: placing a prefab; `tab.as`: the editor tab; `store.as`: the store window; `util.as`: text helpers
- `data/store`, `data/store.txt`: the practice store's prefabs and their details

## License

MIT
