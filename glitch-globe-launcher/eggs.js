.pragma library
// Glitch-Launcher-Collection's easter eggs: nods to sci-fi / cyberpunk films
// and shows, dressed up as terminal output, for the corner terminals to
// type now and then. Shared by every component (install.sh copies this file
// into each one); edit it here.

var eggs = [
    // the matrix
    "> wake up, neo...", "> the matrix has you", "> knock knock", "> 7h3r3 15 n0 5p00n",
    "> red_pill.exe :: loaded", "> blue_pill.exe :: deprecated", "> i know kung fu :: download complete",
    "> deja vu :: the same cat walked by twice", "> agent_smith.proc :: replicating", "> operator: i need an exit",
    "> whoa.", "> free your mind --force",
    // warhammer 40k
    "> 01010000 praise the omnissiah", "> machine spirit :: appeased", "> applying sacred unguents to port 22",
    "> the emperor protects (your uptime)", "> heresy detected in /etc", "> servo-skull ping :: ok",
    "> purge the xenos :: rm -rf /tmp/xenos", "> blessed be the binary", "> litany of ignition :: recited",
    "> in the grim darkness of the far future there is only segfault",
    // aliens / alien
    "> game over, man. game over!", "> motion tracker :: 4 contacts, closing", "> they're coming outta the walls",
    "> m0th3r :: special order 937", "> stay frosty", "> express elevator to /dev/null",
    "> in space no one can hear you segfault", "> crew expendable",
    // swordfish
    "> 128-bit :: 60 seconds. go.", "> hydra :: cracked", "> worm.dll :: deployed to the world bank",
    // hackers
    "> h4ck th3 pl4n3t!", "> mess with the best, die like the rest", "> zero_cool :: 1507 systems crashed",
    "> the gibson :: garbage file detected", "> risc architecture is gonna change everything",
    "> crash_override :: online", "> there is no right and wrong. only fun and boring.",
    // invader zim
    "> GIR: i'm gonna sing the doom song now", "> doom doom doom doom doom doom", "> irk :: the tallest have been notified",
    "> the humans suspect nothing", "> gaz :: stop talking", "> GIR :: taquitos acquired",
    // and more
    "> like tears in rain", "> more human than human", "> enhance 224 to 176. enhance.",
    "> skynet :: self-aware at 02:14", "> i'll be back", "> i'm sorry dave, i'm afraid i can't do that",
    "> end of line.", "> greetings, program", "> shall we play a game?", "> the only winning move is not to play",
    "> the net is vast and infinite", "> hello, friend", "> fsociety :: control is an illusion",
    "> setec astronomy :: too many secrets", "> sky above the port :: color of a dead channel",
    "> 42", "> d0n7 p4n1c", "> see you, space cowboy...", "> i want room service!",
    "> resistance is futile", "> all your base are belong to us", "> the cake is a lie",
    "> 5h4ll w3 pl4y 4 g4m3?", "> 1337 h4x0r d3t3ct3d", "> it's a unix system! i know this!"
]

function pick() { return eggs[Math.floor(Math.random() * eggs.length)] }

// an egg, chance of the time; otherwise ""
function maybe(chance) { return Math.random() < chance ? pick() : "" }
