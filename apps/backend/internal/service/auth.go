package service

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"

	"github.com/JonnyWalker81/trendy/backend/internal/models"
	"github.com/JonnyWalker81/trendy/backend/internal/repository"
	"github.com/JonnyWalker81/trendy/backend/pkg/supabase"
)

type authService struct {
	client   *supabase.Client
	userRepo repository.UserRepository
}

// NewAuthService creates a new auth service
func NewAuthService(client *supabase.Client, userRepo repository.UserRepository) AuthService {
	return &authService{
		client:   client,
		userRepo: userRepo,
	}
}

func (s *authService) Login(ctx context.Context, req *models.LoginRequest) (*models.AuthResponse, error) {
	// Use Supabase Auth API to login
	url := fmt.Sprintf("%s/auth/v1/token?grant_type=password", s.client.URL)

	reqBody := map[string]string{
		"email":    req.Email,
		"password": req.Password,
	}

	jsonData, err := json.Marshal(reqBody)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal request: %w", err)
	}

	httpReq, err := http.NewRequest("POST", url, bytes.NewBuffer(jsonData))
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	httpReq.Header.Set("apikey", s.client.ServiceKey)
	httpReq.Header.Set("Content-Type", "application/json")

	resp, err := s.client.HTTPClient.Do(httpReq)
	if err != nil {
		return nil, fmt.Errorf("failed to login: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response: %w", err)
	}

	if resp.StatusCode >= 400 {
		return nil, fmt.Errorf("login failed: %s", string(body))
	}

	var authResp struct {
		AccessToken  string `json:"access_token"`
		RefreshToken string `json:"refresh_token"`
		User         struct {
			ID    string `json:"id"`
			Email string `json:"email"`
		} `json:"user"`
	}

	if err := json.Unmarshal(body, &authResp); err != nil {
		return nil, fmt.Errorf("failed to unmarshal response: %w", err)
	}

	return &models.AuthResponse{
		AccessToken:  authResp.AccessToken,
		RefreshToken: authResp.RefreshToken,
		User: models.User{
			ID:    authResp.User.ID,
			Email: authResp.User.Email,
		},
	}, nil
}

func (s *authService) Signup(ctx context.Context, req *models.SignupRequest) (*models.AuthResponse, error) {
	// Use Supabase Auth API to signup
	url := fmt.Sprintf("%s/auth/v1/signup", s.client.URL)

	reqBody := map[string]string{
		"email":    req.Email,
		"password": req.Password,
	}

	jsonData, err := json.Marshal(reqBody)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal request: %w", err)
	}

	httpReq, err := http.NewRequest("POST", url, bytes.NewBuffer(jsonData))
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	httpReq.Header.Set("apikey", s.client.ServiceKey)
	httpReq.Header.Set("Content-Type", "application/json")

	resp, err := s.client.HTTPClient.Do(httpReq)
	if err != nil {
		return nil, fmt.Errorf("failed to signup: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response: %w", err)
	}

	if resp.StatusCode >= 400 {
		return nil, fmt.Errorf("signup failed: %s", string(body))
	}

	var authResp struct {
		AccessToken  string `json:"access_token"`
		RefreshToken string `json:"refresh_token"`
		User         struct {
			ID    string `json:"id"`
			Email string `json:"email"`
		} `json:"user"`
	}

	if err := json.Unmarshal(body, &authResp); err != nil {
		return nil, fmt.Errorf("failed to unmarshal response: %w", err)
	}

	// Create user record in our users table
	user := &models.User{
		ID:    authResp.User.ID,
		Email: authResp.User.Email,
	}

	_, err = s.userRepo.Create(ctx, user)
	if err != nil {
		// User creation might fail if already exists, but that's okay
		// as Supabase already created the auth user
	}

	return &models.AuthResponse{
		AccessToken:  authResp.AccessToken,
		RefreshToken: authResp.RefreshToken,
		User: models.User{
			ID:    authResp.User.ID,
			Email: authResp.User.Email,
		},
	}, nil
}

func (s *authService) GetUserByID(ctx context.Context, userID string) (*models.User, error) {
	return s.userRepo.GetByID(ctx, userID)
}
