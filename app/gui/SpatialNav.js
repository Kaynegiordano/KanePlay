.pragma library

// Returns the item of `items` nearest to `current` in a direction ("up", "down",
// "left" or "right"), comparing their centers in the coordinates of `root`, or null.
// Hidden and disabled items are skipped.
function nearest(items, current, direction, root) {
    if (current === null) {
        return null
    }

    var from = current.mapToItem(root, current.width / 2, current.height / 2)
    var best = null
    var bestScore = Infinity

    for (var i = 0; i < items.length; i++) {
        var item = items[i]
        if (item === current || !item.visible || !item.enabled || item.width === 0) {
            continue
        }

        var to = item.mapToItem(root, item.width / 2, item.height / 2)
        var dx = to.x - from.x
        var dy = to.y - from.y
        var along, across

        if (direction === "down") {
            along = dy
            across = Math.abs(dx)
        }
        else if (direction === "up") {
            along = -dy
            across = Math.abs(dx)
        }
        else if (direction === "right") {
            along = dx
            across = Math.abs(dy)
        }
        else {
            along = -dx
            across = Math.abs(dy)
        }

        // Only items ahead, favoring the ones in line with the current one
        if (along <= 4) {
            continue
        }

        var score = along + across * 2
        if (score < bestScore) {
            bestScore = score
            best = item
        }
    }

    return best
}
