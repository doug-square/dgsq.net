#!/bin/bash    
SRC="$(pwd)/src"
OUT="$(pwd)/public"

rm -rf "/${OUT}"
mkdir -p "/${OUT}"

cp -r "$SRC"/assets "$OUT"
cp -r "$SRC"/root/. "$OUT"

# shellcheck disable=SC2044
for page in $(find "$SRC"/pages -type f)
do
  page_name=''${page#"$SRC"/pages}

  if [[ $(dirname "$page_name") != "." ]]
  then
    mkdir -p "$OUT/$(dirname "$page_name")"
  fi

  {
    cat "$SRC/pre.html"
    cat "$page"
    cat "$SRC/post.html"
  } >> "$OUT/$page_name"
done

python list_articles.py

echo "generated site content from $SRC into $OUT"

