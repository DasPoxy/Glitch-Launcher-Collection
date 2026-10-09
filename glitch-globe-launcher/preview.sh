#!/bin/bash
# Glitch-Globe-Launcher's file preview helper: what a file is, and something to show
# of it. Prints one header line, "path<TAB>kind<TAB>mime<TAB>size<TAB>modified",
# then a body by kind:
#   text     its first lines           archive  what's in it
#   pdf      a thumbnail of page 1     audio    its tags and length
#   model    nothing: FilePreview runs render-model.py for a turntable
#   other    file(1)'s description    (image / video: nothing, shown directly)
# usage: preview.sh FILE THUMB_DIR

f=$1
thumbs=$2

mime=$(file -b --mime-type -- "$f" 2>/dev/null)
size=$(stat -c %s -- "$f" 2>/dev/null || echo 0)
modified=$(stat -c %y -- "$f" 2>/dev/null | cut -d. -f1)

ext=${f##*.}
case ${ext,,} in
  stl | 3mf | obj) mime="model/${ext,,}" ;;
esac

case $mime in
  model/*) kind=model ;;
  image/*) kind=image ;;
  video/*) kind=video ;;
  audio/*) kind=audio ;;
  application/pdf) kind=pdf ;;
  text/* | inode/x-empty | application/json | application/javascript | application/xml | \
  application/toml | application/x-*script* | application/x-desktop | application/x-subrip) kind=text ;;
  application/zip | application/x-tar | application/gzip | application/x-xz | application/x-7z-compressed | \
  application/vnd.rar | application/x-rar | application/zstd | application/x-bzip2 | application/java-archive) kind=archive ;;
  *) kind=other ;;
esac

# secrets stay off the screen (screen shares, streams, someone behind you):
# files named like credentials, or text holding keys and tokens, aren't shown
secret_name() {
  case ${f,,} in
    */client_secret*.json | *credentials* | */.netrc | */gh/hosts.yml | */hub \
    | */rclone/rclone.conf | *.pem | *.key | *.p12 | *.pfx | */id_rsa* | */id_ed25519* | */id_ecdsa* | */id_dsa* \
    | *.kdbx | */.env | */.env.* | */secrets.* | *token*.json | *token*.txt | */auth.json | *.gpg | */keyring*) return 0 ;;
  esac
  return 1
}
secret_text() {
  head -c 16000 -- "$f" 2>/dev/null | grep -a -q -i -E \
    'BEGIN [A-Z ]*PRIVATE KEY|client_secret|oauth_token|aws_secret_access_key|xox[bpas]-|gh[pousr]_[A-Za-z0-9]{20,}|"password" *:|^ *password *='
}
if [[ $kind != image && $kind != video && $kind != model ]] && { secret_name || { [[ $kind == text ]] && secret_text; }; }; then
  printf '%s\t%s\t%s\t%s\t%s\n' "$f" "other" "$mime" "$size" "$modified"
  echo "contents hidden: this looks like it holds secrets (keys, tokens, passwords). ENTER still opens it."
  exit 0
fi

printf '%s\t%s\t%s\t%s\t%s\n' "$f" "$kind" "$mime" "$size" "$modified"

case $kind in
  text)
    head -c 16000 -- "$f" | head -n 140 | cut -c1-180
    ;;
  archive)
    bsdtar -tf "$f" 2>/dev/null | head -n 120
    ;;
  pdf)
    mkdir -p "$thumbs"
    out="$thumbs/$(printf '%s:%s' "$f" "$modified" | md5sum | cut -c1-20)"
    [[ -f $out.png ]] || pdftoppm -png -singlefile -r 80 -f 1 -l 1 -- "$f" "$out" 2>/dev/null
    [[ -f $out.png ]] && echo "$out.png"
    ;;
  audio)
    ffprobe -v quiet -show_entries format=duration:format_tags=title,artist,album,date,genre \
      -of default=noprint_wrappers=1 -- "$f" 2>/dev/null | sed 's/^TAG://'
    ;;
  image | video | model) ;;
  *)
    file -b -- "$f" 2>/dev/null
    ;;
esac
