// Package account coordinates cross-domain account operations. Its only job
// today is account deletion (App Store guideline 5.1.1(v)): validating the
// user's household roles, deleting sole-member households, and removing the
// user with all personal data.
package account

import (
	"context"
	"fmt"

	"github.com/HammerMeetNail/nabu/internal/auth"
	"github.com/HammerMeetNail/nabu/internal/household"
)

// ErrMustTransferOwnership is returned when the user is the only owner of a
// household that still has other members. The client should guide the user
// through transferring ownership (or removing the other members) first.
type ErrMustTransferOwnership struct {
	HouseholdName string
}

func (e ErrMustTransferOwnership) Error() string {
	return fmt.Sprintf("you are the only owner of %q; transfer ownership or remove its other members first", e.HouseholdName)
}

type Service struct {
	users      auth.Store
	households household.Store
}

func NewService(users auth.Store, households household.Store) *Service {
	return &Service{users: users, households: households}
}

// DeleteAccount permanently deletes the user. Semantics per household:
//
//   - sole member            → the household and all its data are deleted
//   - only owner, has others → rejected with ErrMustTransferOwnership
//   - otherwise              → equivalent to leaving the household
//
// Validation runs over every membership before anything is mutated, so a
// rejection never leaves a half-deleted account. Personal data (sessions,
// tokens, preferences, notifications, push subscriptions, the user's chore
// logs) is removed; household-shared content in surviving households stays,
// with chore authorship and schedule assignment cleared and the user's
// invites revoked.
func (s *Service) DeleteAccount(ctx context.Context, userID int64) error {
	memberships, err := s.households.ListUserHouseholds(ctx, userID)
	if err != nil {
		return err
	}

	var deleteHouseholds []int64
	var leaveHouseholds []int64
	for _, hh := range memberships {
		members, err := s.households.GetMembers(ctx, hh.ID)
		if err != nil {
			return err
		}
		if len(members) <= 1 {
			deleteHouseholds = append(deleteHouseholds, hh.ID)
			continue
		}
		if hh.Role == household.RoleOwner {
			otherOwner := false
			for _, m := range members {
				if m.UserID != userID && m.Role == household.RoleOwner {
					otherOwner = true
					break
				}
			}
			if !otherOwner {
				return ErrMustTransferOwnership{HouseholdName: hh.Name}
			}
		}
		leaveHouseholds = append(leaveHouseholds, hh.ID)
	}

	for _, hhID := range deleteHouseholds {
		if err := s.households.DeleteHousehold(ctx, hhID); err != nil {
			return err
		}
	}
	// Explicit removal keeps the memory store consistent; in Postgres the
	// membership rows would also cascade with the user row below.
	for _, hhID := range leaveHouseholds {
		if err := s.households.RemoveMember(ctx, hhID, userID); err != nil {
			return err
		}
	}
	return s.users.DeleteUser(ctx, userID)
}
