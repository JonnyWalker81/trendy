package repository

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/JonnyWalker81/trendy/backend/internal/models"
	"github.com/JonnyWalker81/trendy/backend/pkg/supabase"
)

type userRepository struct {
	client *supabase.Client
}

// NewUserRepository creates a new user repository
func NewUserRepository(client *supabase.Client) UserRepository {
	return &userRepository{client: client}
}

func (r *userRepository) GetByID(ctx context.Context, id string) (*models.User, error) {
	query := map[string]interface{}{
		"id": fmt.Sprintf("eq.%s", id),
	}

	body, err := r.client.Query("users", query)
	if err != nil {
		return nil, fmt.Errorf("failed to get user: %w", err)
	}

	var users []models.User
	if err := json.Unmarshal(body, &users); err != nil {
		return nil, fmt.Errorf("failed to unmarshal response: %w", err)
	}

	if len(users) == 0 {
		return nil, fmt.Errorf("user not found")
	}

	return &users[0], nil
}

func (r *userRepository) GetByEmail(ctx context.Context, email string) (*models.User, error) {
	query := map[string]interface{}{
		"email": fmt.Sprintf("eq.%s", email),
	}

	body, err := r.client.Query("users", query)
	if err != nil {
		return nil, fmt.Errorf("failed to get user: %w", err)
	}

	var users []models.User
	if err := json.Unmarshal(body, &users); err != nil {
		return nil, fmt.Errorf("failed to unmarshal response: %w", err)
	}

	if len(users) == 0 {
		return nil, fmt.Errorf("user not found")
	}

	return &users[0], nil
}

func (r *userRepository) Create(ctx context.Context, user *models.User) (*models.User, error) {
	data := map[string]interface{}{
		"id":    user.ID,
		"email": user.Email,
	}

	body, err := r.client.Insert("users", data)
	if err != nil {
		return nil, fmt.Errorf("failed to create user: %w", err)
	}

	var users []models.User
	if err := json.Unmarshal(body, &users); err != nil {
		return nil, fmt.Errorf("failed to unmarshal response: %w", err)
	}

	if len(users) == 0 {
		return nil, fmt.Errorf("no user returned")
	}

	return &users[0], nil
}
