// Placing a prefab: the game's own spawnprefab (Prefabs::Spawn), which puts it in front of the camera as one group,
// selected (measured: "Spawned prefab bench (28 items) in front of the camera.", the 28 new pieces the selection, and
// the selection a group the editor can rename). Then the way new pieces are placed with Create Extensions is kept, for
// the whole prefab at once: moved its "Placement distance" further along the view, and onto whole units by one offset
// for every piece (each piece rounded on its own would pull the prefab apart).

namespace Place
{

// Create Extensions' "Placement distance", or 0 when it isn't running (its settings are only listed while it runs).
double CreateExtensionsDistance()
{
    for (uint i = 0; i < Settings::Count(); i++)
        if (Settings::Plugin(i) == "create-extensions" && Settings::Name(i) == "Placement distance")
            return parseFloat(Settings::Get(i));
    return 0;
}

bool CreateExtensionsRunning()
{
    for (uint i = 0; i < Settings::Count(); i++)
        if (Settings::Plugin(i) == "create-extensions")
            return true;
    return false;
}

// Places prefab `file`; "" when placed, else why not. `count` is how many pieces it has.
string Place(const string &in file, int &out count)
{
    count = 0;
    if (!Editor::IsOpen() || Editor::IsTesting())
        return "open the track editor to place a prefab";
    string reply;
    array<int>@ made = Prefabs::Spawn(file, reply);
    count = int(made.length());
    if (made.length() == 0)
        return reply == "" ? "the game placed nothing" : reply;
    if (!CreateExtensionsRunning())
        return "";
    double distance = CreateExtensionsDistance();
    double fx = 0, fy = 0, fz = 0;
    Editor::ViewForward(fx, fy, fz);
    double x0, y0, z0;
    if (!Editor::GetLocation(made[0], x0, y0, z0))
        return "";
    // the first piece, moved along the view, lands on whole units: every piece moves by the same amount
    double dx = Round(x0 + fx * distance) - x0, dy = Round(y0 + fy * distance) - y0, dz = Round(z0 + fz * distance) - z0;
    if (dx == 0 && dy == 0 && dz == 0)
        return "";
    // the spawn leaves the prefab selected: moved as one, its pivot (the gizmo) with it, in one call
    Editor::MoveSelection(dx, dy, dz);
    return "";
}

}  // namespace Place
