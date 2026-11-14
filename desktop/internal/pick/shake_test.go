package pick

import (
	"testing"
	"time"

	"github.com/pointylab/pointy/desktop/internal/config"
	"github.com/pointylab/pointy/desktop/internal/desktop"
)

// swing feeds a shake of xs, one sample every 16 ms from t0, and reports
// the indexes of the samples that completed a shake.
func swing(s *shaker, t0 time.Time, xs []float64, ys []float64, allowed bool) []int {
	var fired []int
	for i, x := range xs {
		y := 300.0
		if ys != nil {
			y = ys[i]
		}
		if s.feed(t0.Add(time.Duration(i)*16*time.Millisecond), desktop.Point{X: x, Y: y}, config.ShakeMedium, func() bool { return allowed }) {
			fired = append(fired, i)
		}
	}
	return fired
}

var shakeXs = []float64{100, 150, 100, 150, 100, 150, 100}

func TestShakeFiresOnceWhenReversalsReachTheLevel(t *testing.T) {
	var s shaker
	got := swing(&s, time.Unix(0, 0), shakeXs, nil, true)
	if len(got) != 1 || got[0] != 5 {
		t.Fatalf("fired at %v, want once at sample 5", got)
	}
}

func TestShakeWaitsOutTheCooldown(t *testing.T) {
	var s shaker
	t0 := time.Unix(0, 0)
	swing(&s, t0, shakeXs, nil, true)
	if got := swing(&s, t0.Add(500*time.Millisecond), shakeXs, nil, true); len(got) != 0 {
		t.Fatalf("fired again at %v within the cooldown", got)
	}
	if got := swing(&s, t0.Add(2*time.Second), shakeXs, nil, true); len(got) != 1 {
		t.Fatalf("fired at %v after the cooldown, want once", got)
	}
}

func TestShakeFiresAlongDiagonalAndArc(t *testing.T) {
	var diag shaker
	ys := []float64{0, 200, 0, 200, 0, 200, 0}
	if got := swing(&diag, time.Unix(0, 0), shakeXs, ys, true); len(got) != 1 || got[0] != 5 {
		t.Fatalf("diagonal shake fired at %v, want once at sample 5", got)
	}
	var arc shaker
	arcXs := []float64{800, 680, 790, 650, 780, 660, 770}
	arcYs := []float64{100, 290, 130, 350, 150, 330, 170}
	if got := swing(&arc, time.Unix(0, 0), arcXs, arcYs, true); len(got) != 1 || got[0] != 5 {
		t.Fatalf("arc shake fired at %v, want once at sample 5", got)
	}
}

func TestShakeIgnoresLongSweep(t *testing.T) {
	var s shaker
	xs := []float64{100, 260, 430, 610, 790, 960, 1120}
	ys := []float64{700, 600, 490, 390, 290, 200, 120}
	if got := swing(&s, time.Unix(0, 0), xs, ys, true); len(got) != 0 {
		t.Fatalf("fired at %v for a one-way sweep across the screen", got)
	}
}

func TestShakeIgnoresWideDriftAcrossSwing(t *testing.T) {
	var drift shaker
	ys := []float64{0, 50, 100, 150, 200, 250, 300}
	if got := swing(&drift, time.Unix(0, 0), shakeXs, ys, true); len(got) != 0 {
		t.Fatalf("fired at %v while sweeping vertically with a small horizontal wobble", got)
	}
	var loop shaker
	loopXs := []float64{100, 150, 200, 150, 100, 150, 200, 150, 100}
	loopYs := []float64{150, 200, 150, 100, 150, 200, 150, 100, 150}
	if got := swing(&loop, time.Unix(0, 0), loopXs, loopYs, true); len(got) != 0 {
		t.Fatalf("fired at %v for a circular movement", got)
	}
}

func TestShakeForgetsSamplesOutsideTheWindow(t *testing.T) {
	var s shaker
	t0 := time.Unix(0, 0)
	for i, x := range shakeXs[:4] {
		s.feed(t0.Add(time.Duration(i)*200*time.Millisecond), desktop.Point{X: x, Y: 300}, config.ShakeMedium, func() bool { return true })
	}
	if len(s.samples) != 3 {
		t.Fatalf("kept %d samples, want the 3 within 450 ms", len(s.samples))
	}
}

func TestShakeNotAllowedDoesNotFireOrCoolDown(t *testing.T) {
	var s shaker
	t0 := time.Unix(0, 0)
	if got := swing(&s, t0, shakeXs, nil, false); len(got) != 0 {
		t.Fatalf("fired at %v while not allowed", got)
	}
	if got := swing(&s, t0.Add(200*time.Millisecond), shakeXs, nil, true); len(got) != 1 {
		t.Fatalf("fired at %v once allowed, want once", got)
	}
}
