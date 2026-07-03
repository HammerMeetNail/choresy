package push

import "context"

// DataSender is the shape shared by the Web Push service and the APNs client:
// plain sends plus the data-carrying variant the reminder scheduler
// type-asserts for.
type DataSender interface {
	SendPushToUser(ctx context.Context, userID int64, title, body string) error
	SendPushToUserWithData(ctx context.Context, userID int64, title, body string, data map[string]any) error
}

// FanoutSender delivers every push to all configured channels (Web Push for
// the PWA, APNs for the native app). Channel errors don't short-circuit the
// others; the first error is returned for observability.
type FanoutSender struct {
	senders []DataSender
}

func NewFanoutSender(senders ...DataSender) *FanoutSender {
	return &FanoutSender{senders: senders}
}

func (f *FanoutSender) SendPushToUser(ctx context.Context, userID int64, title, body string) error {
	return f.SendPushToUserWithData(ctx, userID, title, body, nil)
}

func (f *FanoutSender) SendPushToUserWithData(ctx context.Context, userID int64, title, body string, data map[string]any) error {
	var firstErr error
	for _, s := range f.senders {
		if err := s.SendPushToUserWithData(ctx, userID, title, body, data); err != nil && firstErr == nil {
			firstErr = err
		}
	}
	return firstErr
}
