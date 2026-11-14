package pick

import (
	"testing"

	"github.com/pointylab/pointy/desktop/internal/desktop"
)

func TestCountReversals(t *testing.T) {
	cases := []struct {
		name string
		xs   []float64
		want int
	}{
		{"moving in one direction is not a shake", []float64{0, 20, 40, 60, 80, 100, 120}, 0},
		{"each swing back of at least the amplitude counts once", []float64{0, 50, 0, 50, 0}, 3},
		{"jitter smaller than the amplitude is ignored", []float64{0, 30, 0, 30, 0, 30}, 0},
		{"jitter around a far point is ignored", []float64{0, 60, 30, 60, 30, 60}, 0},
		{"a swing is measured from the farthest point reached", []float64{0, 50, 100, 70}, 0},
		{"a swing from the farthest point counts", []float64{0, 50, 100, 70, 40}, 1},
		{"the first leg must travel the amplitude before direction is set", []float64{100, 70, 100, 70}, 0},
		{"a first leg that travels the amplitude sets the direction", []float64{100, 70, 50, 90, 60}, 1},
		{"a lone sample has no reversals", []float64{10}, 0},
		{"no samples have no reversals", nil, 0},
	}
	for _, c := range cases {
		if got := countReversals(c.xs, 40); got != c.want {
			t.Errorf("%s: countReversals(%v) = %d, want %d", c.name, c.xs, got, c.want)
		}
	}
}

func TestProjectMainAxis(t *testing.T) {
	cases := []struct {
		name string
		pts  []desktop.Point
		want int
	}{
		{"vertical swings count along y", []desktop.Point{{X: 200, Y: 0}, {X: 200, Y: 50}, {X: 200, Y: 0}, {X: 200, Y: 50}, {X: 200, Y: 0}}, 3},
		{"diagonal swings combine x and y amplitude", []desktop.Point{{X: 0, Y: 0}, {X: 30, Y: 30}, {X: 0, Y: 0}, {X: 30, Y: 30}, {X: 0, Y: 0}}, 3},
		{"a long diagonal sweep has no reversals", []desktop.Point{{X: 0, Y: 600}, {X: 200, Y: 480}, {X: 420, Y: 350}, {X: 650, Y: 210}, {X: 900, Y: 60}}, 0},
		{"a pause before shaking does not skew the axis", []desktop.Point{
			{X: 500, Y: 540}, {X: 500, Y: 540}, {X: 500, Y: 540}, {X: 500, Y: 540},
			{X: 500, Y: 540}, {X: 500, Y: 540}, {X: 500, Y: 540}, {X: 500, Y: 540},
			{X: 450, Y: 500}, {X: 500, Y: 500}, {X: 450, Y: 500}, {X: 500, Y: 500},
		}, 3},
	}
	for _, c := range cases {
		along, _, _ := projectMainAxis(c.pts)
		if got := countReversals(along, 40); got != c.want {
			t.Errorf("%s: countReversals(projectMainAxis(%v)) = %d, want %d", c.name, c.pts, got, c.want)
		}
	}
}
