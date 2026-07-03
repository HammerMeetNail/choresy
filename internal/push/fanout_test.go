package push

import (
	"context"
	"errors"
	"testing"
)

type recordingSender struct {
	calls int
	data  map[string]any
	err   error
}

func (r *recordingSender) SendPushToUser(ctx context.Context, userID int64, title, body string) error {
	return r.SendPushToUserWithData(ctx, userID, title, body, nil)
}

func (r *recordingSender) SendPushToUserWithData(_ context.Context, _ int64, _, _ string, data map[string]any) error {
	r.calls++
	r.data = data
	return r.err
}

func TestFanoutSender_DeliversToAllChannels(t *testing.T) {
	web := &recordingSender{}
	apns := &recordingSender{}
	fanout := NewFanoutSender(web, apns)

	data := map[string]any{"choreId": 5}
	if err := fanout.SendPushToUserWithData(context.Background(), 1, "t", "b", data); err != nil {
		t.Fatalf("SendPushToUserWithData: %v", err)
	}
	if web.calls != 1 || apns.calls != 1 {
		t.Fatalf("calls: web=%d apns=%d, want 1 each", web.calls, apns.calls)
	}
	if web.data["choreId"] != 5 || apns.data["choreId"] != 5 {
		t.Fatal("data fields must reach every channel")
	}
}

func TestFanoutSender_OneFailureDoesNotBlockOthers(t *testing.T) {
	failing := &recordingSender{err: errors.New("boom")}
	healthy := &recordingSender{}
	fanout := NewFanoutSender(failing, healthy)

	err := fanout.SendPushToUser(context.Background(), 1, "t", "b")
	if err == nil || err.Error() != "boom" {
		t.Fatalf("err = %v, want first channel error surfaced", err)
	}
	if healthy.calls != 1 {
		t.Fatal("second channel must still be attempted")
	}
}

func TestFanoutSender_EmptyIsNoop(t *testing.T) {
	if err := NewFanoutSender().SendPushToUser(context.Background(), 1, "t", "b"); err != nil {
		t.Fatalf("empty fanout should no-op, got %v", err)
	}
}
