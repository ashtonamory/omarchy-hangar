.pragma library

// Rank projects against the typed filter. Empty filter keeps the scan order
// (most recently active first). Otherwise: name prefix, then a word start in
// the name, then anywhere in the name, then a match on the branch, then the
// letters in order (fuzzy). Ties keep the activity order.
function filter(projects, text) {
  var list = Array.isArray(projects) ? projects : []
  var q = String(text || "").toLowerCase().trim()
  if (!q) return list.slice()

  var scored = []
  for (var i = 0; i < list.length; i++) {
    var p = list[i] || {}
    var s = score(String(p.name || "").toLowerCase(), String(p.branch || "").toLowerCase(), q)
    if (s > 0) scored.push({ p: p, s: s, i: i })
  }
  scored.sort(function(a, b) { return b.s - a.s || a.i - b.i })
  return scored.map(function(x) { return x.p })
}

function score(name, branch, q) {
  if (name.indexOf(q) === 0) return 100
  var at = name.indexOf(q)
  if (at > 0) {
    var before = name.charAt(at - 1)
    return (before === "-" || before === "_" || before === "." || before === " ") ? 80 : 60
  }
  if (branch.indexOf(q) >= 0) return 40
  return subsequence(name, q) ? 20 : 0
}

function subsequence(hay, q) {
  var j = 0
  for (var i = 0; i < hay.length && j < q.length; i++) if (hay.charAt(i) === q.charAt(j)) j++
  return j === q.length
}
