import nimaid/emoji
doAssert loadEmojiFont("/home/claude/emoji/NotoColorEmoji-Regular.ttf")
writeFile("/tmp/e_smile.svg", emojiSvg("😀"))
writeFile("/tmp/e_flag.svg", emojiSvg("🇺🇳"))
writeFile("/tmp/e_fam.svg", emojiSvg("👨‍👩‍👧"))
