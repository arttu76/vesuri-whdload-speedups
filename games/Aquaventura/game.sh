# games/Aquaventura/game.sh: hooks for what game.conf cannot express.

# game_unpack: install tmp/game/Aquaventura as the package's Install script does with RawDIC.
# The install package holds the slave and the docs; the disk images come from the two IPFs,
# decoded with the SPS capsimg library ($CAPSIMG) by tools/ipf2disk.py into disk.1 and disk.2.
CAPSIMG="${CAPSIMG:-$AMIGA_SHARE/capsimg/capsimg.so}"

game_unpack() {
  local dest="tmp/game/Aquaventura" stage pkg d
  if [ -e "$dest" ]; then
    if [ "${FORCE:-0}" = 1 ]; then rm -rf "$dest"; else
      echo "kept the existing $dest (FORCE=1 replaces it)"; return 0
    fi
  fi
  [ -f "$CAPSIMG" ] || die "no capsimg library at $CAPSIMG (set CAPSIMG)"
  stage="$(mktemp -d "$GAME_ROOT/tmp/unpack.XXXXXX")"
  "$LHA" "xqw=$stage" "tmp/archives/Aquaventura.lha"
  pkg="$stage/AquaventuraHD"
  mkdir -p "$stage/Aquaventura"
  cp "$pkg/Aquaventura.slave" "$stage/Aquaventura/"
  cp "$pkg/Aquaventura.readme" "$stage/Aquaventura/ReadMe"
  cp "$pkg/Aquaventura.inf" "$stage/Aquaventura/Aquaventura.info"
  for d in 1 2; do
    python3 -I tools/ipf2disk.py "$CAPSIMG" "$d" "tmp/archives/Aquaventura_Disk$d.ipf" \
      "$stage/Aquaventura/disk.$d"
  done
  mkdir -p tmp/game
  mv "$stage/Aquaventura" "$dest"
  rm -rf "$stage"
  echo "unpacked $dest"
}
