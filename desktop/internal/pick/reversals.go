package pick

import (
	"math"

	"github.com/pointylab/pointy/desktop/internal/desktop"
)

// projectMainAxis projects pts onto their principal direction and returns
// the coordinates along that axis, the span along it, and the span across it.
func projectMainAxis(pts []desktop.Point) (along []float64, mainSpan, crossSpan float64) {
	if len(pts) == 0 {
		return nil, 0, 0
	}
	ux, uy := mainAxis(pts)
	along = make([]float64, len(pts))
	origin := pts[0]
	var alongMin, alongMax, crossMin, crossMax float64
	for i, p := range pts {
		dx, dy := p.X-origin.X, p.Y-origin.Y
		a := dx*ux + dy*uy
		c := -dx*uy + dy*ux
		along[i] = a
		alongMin, alongMax = min(alongMin, a), max(alongMax, a)
		crossMin, crossMax = min(crossMin, c), max(crossMax, c)
	}
	return along, alongMax - alongMin, crossMax - crossMin
}

// mainAxis returns a unit vector along the principal direction of pts,
// ignoring consecutive duplicate positions so a pause does not skew it.
func mainAxis(pts []desktop.Point) (ux, uy float64) {
	var mx, my float64
	n := 0
	for i, p := range pts {
		if i > 0 && p == pts[i-1] {
			continue
		}
		mx += p.X
		my += p.Y
		n++
	}
	if n < 2 {
		return 1, 0
	}
	mx /= float64(n)
	my /= float64(n)
	var sxx, syy, sxy float64
	for i, p := range pts {
		if i > 0 && p == pts[i-1] {
			continue
		}
		dx, dy := p.X-mx, p.Y-my
		sxx += dx * dx
		syy += dy * dy
		sxy += dx * dy
	}
	d := sxx - syy
	h := math.Hypot(d, 2*sxy)
	if h == 0 {
		return 1, 0
	}
	if d >= 0 {
		ux = math.Sqrt((h + d) / (2 * h))
		return ux, sxy / (h * ux)
	}
	uy = math.Sqrt((h - d) / (2 * h))
	return sxy / (h * uy), uy
}

// countReversals counts how often xs turns back after travelling at least
// amplitude from the farthest point it reached.
func countReversals(xs []float64, amplitude float64) int {
	if len(xs) == 0 {
		return 0
	}
	reversals := 0
	dir := 0.0
	extreme := xs[0]
	for _, x := range xs[1:] {
		if dir == 0 {
			if abs(x-extreme) >= amplitude {
				dir, extreme = sign(x-extreme), x
			}
			continue
		}
		if (x-extreme)*dir > 0 {
			extreme = x
			continue
		}
		if abs(extreme-x) >= amplitude {
			reversals++
			dir, extreme = -dir, x
		}
	}
	return reversals
}

func abs(x float64) float64 { return max(x, -x) }

func sign(x float64) float64 {
	switch {
	case x > 0:
		return 1
	case x < 0:
		return -1
	}
	return 0
}
