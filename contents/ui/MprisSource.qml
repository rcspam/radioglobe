import org.kde.plasma.private.mpris as Mpris

// Kept in its own file so main.qml can Loader-load it: if the private MPRIS
// module ever disappears, only this component fails to load.
Mpris.Mpris2Model {}
