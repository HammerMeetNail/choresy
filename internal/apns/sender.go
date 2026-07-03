package apns

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"log"
	"net/http"
	"time"
)

const (
	hostSandbox    = "https://api.sandbox.push.apple.com"
	hostProduction = "https://api.push.apple.com"
)

// Client sends alert pushes to a user's registered devices. It implements
// the same SendPushToUser / SendPushToUserWithData shape as the Web Push
// service so the two can sit behind one fan-out sender.
type Client struct {
	store  Store
	signer *ProviderTokenSigner
	// topic is the apns-topic header — the app's bundle ID.
	topic      string
	httpClient *http.Client

	// hostOverride redirects both environments to one base URL; used by
	// tests to point the client at a fake APNs server.
	hostOverride string
}

func NewClient(store Store, signer *ProviderTokenSigner, topic string) *Client {
	// Go's http.Client negotiates HTTP/2 for https endpoints automatically,
	// which is all APNs requires.
	return &Client{
		store:      store,
		signer:     signer,
		topic:      topic,
		httpClient: &http.Client{Timeout: 10 * time.Second},
	}
}

func (c *Client) host(environment string) string {
	if c.hostOverride != "" {
		return c.hostOverride
	}
	if environment == EnvironmentSandbox {
		return hostSandbox
	}
	return hostProduction
}

func (c *Client) SendPushToUser(ctx context.Context, userID int64, title, body string) error {
	return c.SendPushToUserWithData(ctx, userID, title, body, nil)
}

// SendPushToUserWithData delivers an alert push to every device the user has
// registered. Extra data fields (choreId, type, …) ride alongside the aps
// dictionary for the client's notification handling; a "category" field maps
// to aps.category so action buttons can attach. Per-device errors are logged,
// not returned, so one dead token doesn't block the rest; terminally invalid
// tokens are pruned.
func (c *Client) SendPushToUserWithData(ctx context.Context, userID int64, title, body string, data map[string]any) error {
	if c == nil || c.signer == nil {
		return nil // APNs not configured
	}
	devices, err := c.store.DevicesForUser(ctx, userID)
	if err != nil {
		log.Printf("apns: devices for user %d: %v", userID, err)
		return err
	}
	if len(devices) == 0 {
		return nil
	}

	payload, err := c.buildPayload(title, body, data)
	if err != nil {
		return err
	}

	for _, device := range devices {
		c.sendToDevice(ctx, device, payload)
	}
	return nil
}

func (c *Client) buildPayload(title, body string, data map[string]any) ([]byte, error) {
	aps := map[string]any{
		"alert": map[string]string{"title": title, "body": body},
		"sound": "default",
	}
	fields := map[string]any{}
	for k, v := range data {
		switch k {
		case "title", "body", "aps":
			continue
		case "category":
			if s, ok := v.(string); ok && s != "" {
				aps["category"] = s
			}
		default:
			fields[k] = v
		}
	}
	fields["aps"] = aps
	return json.Marshal(fields)
}

func (c *Client) sendToDevice(ctx context.Context, device Device, payload []byte) {
	token, err := c.signer.Token()
	if err != nil {
		log.Printf("apns: provider token: %v", err)
		return
	}

	url := c.host(device.Environment) + "/3/device/" + device.Token
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(payload))
	if err != nil {
		log.Printf("apns: create request: %v", err)
		return
	}
	req.Header.Set("Authorization", "bearer "+token)
	req.Header.Set("apns-topic", c.topic)
	req.Header.Set("apns-push-type", "alert")
	req.Header.Set("apns-priority", "10")
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		log.Printf("apns: send to user %d device %s…: %v", device.UserID, safePrefix(device.Token), err)
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusOK {
		log.Printf("apns: sent to user %d device %s… status=200", device.UserID, safePrefix(device.Token))
		return
	}

	respBody, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
	var apnsErr struct {
		Reason string `json:"reason"`
	}
	_ = json.Unmarshal(respBody, &apnsErr)
	log.Printf("apns: send to user %d device %s… status=%d reason=%q",
		device.UserID, safePrefix(device.Token), resp.StatusCode, apnsErr.Reason)

	// 410 Unregistered means the token is gone for good; BadDeviceToken means
	// it was never valid for this environment. Both are terminal — prune.
	if resp.StatusCode == http.StatusGone || apnsErr.Reason == "BadDeviceToken" || apnsErr.Reason == "Unregistered" {
		if err := c.store.DeleteToken(ctx, device.Token); err != nil {
			log.Printf("apns: prune token %s…: %v", safePrefix(device.Token), err)
		}
	}
}

func safePrefix(token string) string {
	if len(token) <= 8 {
		return token
	}
	return token[:8]
}
