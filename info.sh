#!/bin/bash
# Globe-Launcher's terminal readout for a file: a few "key value" lines the
# corner terminal types out when you linger on it.
# usage: info.sh FILE

f=$1
[[ -e $f ]] || { echo "status  missing"; exit 0; }

mime=$(file -b --mime-type -- "$f" 2>/dev/null)
size=$(stat -c %s -- "$f" 2>/dev/null || echo 0)
human() { numfmt --to=iec-i --suffix=B --format=%.1f "$1" 2>/dev/null || echo "$1 B"; }

echo "type    $mime"
echo "size    $(human "$size")"
echo "mod     $(stat -c %y -- "$f" 2>/dev/null | cut -d. -f1)"

case $mime in
  video/* | audio/*)
    ffprobe -v quiet -select_streams v:0 -show_entries stream=width,height,codec_name:format=duration,bit_rate \
      -of default=noprint_wrappers=1 -- "$f" 2>/dev/null | awk -F= '
        /^duration=/ { d = $2 } /^width=/ { w = $2 } /^height=/ { h = $2 } /^codec_name=/ { c = $2 } /^bit_rate=/ { b = $2 }
        END {
          if (d != "" && d != "N/A") printf "length  %d:%02d\n", d / 60, d % 60
          if (w != "") printf "frame   %sx%s  %s\n", w, h, c
          if (b != "" && b != "N/A") printf "rate    %d kb/s\n", b / 1000
        }'
    ;;
  image/*)
    dims=$(ffprobe -v quiet -select_streams v:0 -show_entries stream=width,height -of csv=p=0:s=x -- "$f" 2>/dev/null)
    [[ -n $dims ]] && echo "pixels  $dims"
    ;;
  text/* | application/json | application/xml | application/x-*script*)
    echo "lines   $(wc -l < "$f" 2>/dev/null)"
    ;;
  application/pdf)
    pages=$(pdfinfo -- "$f" 2>/dev/null | awk '/^Pages:/ { print $2 }')
    [[ -n $pages ]] && echo "pages   $pages"
    ;;
  application/zip | application/x-tar | application/gzip | application/x-xz | application/x-7z-compressed | application/zstd)
    echo "entries $(bsdtar -tf "$f" 2>/dev/null | wc -l)"
    ;;
esac
case ${f,,} in
  *.stl)
    # binary STL: the triangle count is in the header
    n=$(python3 -c 'import struct,sys,os; f=open(sys.argv[1],"rb"); f.seek(80); n=struct.unpack("<I",f.read(4))[0]; print(n if 84+n*50==os.path.getsize(sys.argv[1]) else "")' "$f" 2>/dev/null)
    [[ -n $n ]] && echo "tris    $n"
    echo "model   STL" ;;
  *.3mf) echo "model   3MF" ;;
  *.obj) echo "model   OBJ" ;;
esac
[[ -x $f && ! -d $f ]] && echo "mode    executable"
exit 0
