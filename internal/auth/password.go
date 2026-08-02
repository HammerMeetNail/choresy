package auth

import (
	"golang.org/x/crypto/bcrypt"
)

const bcryptCost = 13

// dummyPasswordHash is a precomputed bcrypt (cost 13) hash of a random 32-byte
// throwaway password whose plaintext was discarded. Login compares against it
// when the email is unknown so the miss path costs the same as a real bcrypt
// compare (~250-400 ms), removing the login timing oracle that otherwise
// reveals whether an email is registered. Nothing can authenticate against it.
var dummyPasswordHash = "$2a$13$A2i1s/lLZ64.tSfuAnMWSeQHvW8FJCRYMYo2Omvi.mcqtrIkw61pq"

func hashPassword(password string) (string, error) {
	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcryptCost)
	if err != nil {
		return "", err
	}
	return string(hash), nil
}

func verifyPassword(hash, password string) error {
	return bcrypt.CompareHashAndPassword([]byte(hash), []byte(password))
}
