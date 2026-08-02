package household

import "errors"

var (
	ErrNotFound       = errors.New("household not found")
	ErrAlreadyMember  = errors.New("user is already a member of a household")
	ErrNotMember      = errors.New("user is not a member of this household")
	ErrInviteNotFound = errors.New("invite not found")
	ErrInviteExpired  = errors.New("invite has expired")
	ErrLastOwner      = errors.New("cannot remove the last owner")
	ErrNotAuthorized  = errors.New("not authorized")
	// ErrInvalidInput marks request data that failed per-field validation
	// (audit finding #10). Handlers map it to 400 with the wrapped message.
	ErrInvalidInput = errors.New("invalid input")
)

const MaxMembersPerHousehold = 20
