package supabase

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
)

// Client represents a Supabase client
type Client struct {
	URL        string
	ServiceKey string
	HTTPClient *http.Client
}

// NewClient creates a new Supabase client
func NewClient(url, serviceKey string) *Client {
	return &Client{
		URL:        url,
		ServiceKey: serviceKey,
		HTTPClient: &http.Client{},
	}
}

// Query executes a query on a Supabase table
func (c *Client) Query(table string, query map[string]interface{}) ([]byte, error) {
	return c.QueryWithToken(table, query, "")
}

// QueryWithToken executes a query with an optional user JWT token for RLS
func (c *Client) QueryWithToken(table string, query map[string]interface{}, userToken string) ([]byte, error) {
	url := fmt.Sprintf("%s/rest/v1/%s", c.URL, table)

	// Build query parameters
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return nil, err
	}

	q := req.URL.Query()
	for key, value := range query {
		q.Add(key, fmt.Sprintf("%v", value))
	}
	req.URL.RawQuery = q.Encode()

	req.Header.Set("apikey", c.ServiceKey)

	// Use user token if provided, otherwise use service key
	if userToken != "" {
		req.Header.Set("Authorization", fmt.Sprintf("Bearer %s", userToken))
	} else {
		req.Header.Set("Authorization", fmt.Sprintf("Bearer %s", c.ServiceKey))
	}

	resp, err := c.HTTPClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	if resp.StatusCode >= 400 {
		return nil, fmt.Errorf("supabase error: %s", string(body))
	}

	return body, nil
}

// Insert inserts a record into a Supabase table
func (c *Client) Insert(table string, data interface{}) ([]byte, error) {
	return c.InsertWithToken(table, data, "")
}

// InsertWithToken inserts a record with an optional user JWT token for RLS
func (c *Client) InsertWithToken(table string, data interface{}, userToken string) ([]byte, error) {
	url := fmt.Sprintf("%s/rest/v1/%s", c.URL, table)

	jsonData, err := json.Marshal(data)
	if err != nil {
		return nil, err
	}

	req, err := http.NewRequest("POST", url, bytes.NewBuffer(jsonData))
	if err != nil {
		return nil, err
	}

	req.Header.Set("apikey", c.ServiceKey)

	// Use user token if provided, otherwise use service key
	if userToken != "" {
		req.Header.Set("Authorization", fmt.Sprintf("Bearer %s", userToken))
	} else {
		req.Header.Set("Authorization", fmt.Sprintf("Bearer %s", c.ServiceKey))
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Prefer", "return=representation")

	resp, err := c.HTTPClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	if resp.StatusCode >= 400 {
		return nil, fmt.Errorf("supabase error: %s", string(body))
	}

	return body, nil
}

// Update updates a record in a Supabase table
func (c *Client) Update(table string, id string, data interface{}) ([]byte, error) {
	return c.UpdateWithToken(table, id, data, "")
}

// UpdateWithToken updates a record with an optional user JWT token for RLS
func (c *Client) UpdateWithToken(table string, id string, data interface{}, userToken string) ([]byte, error) {
	url := fmt.Sprintf("%s/rest/v1/%s?id=eq.%s", c.URL, table, id)

	jsonData, err := json.Marshal(data)
	if err != nil {
		return nil, err
	}

	req, err := http.NewRequest("PATCH", url, bytes.NewBuffer(jsonData))
	if err != nil {
		return nil, err
	}

	req.Header.Set("apikey", c.ServiceKey)

	// Use user token if provided, otherwise use service key
	if userToken != "" {
		req.Header.Set("Authorization", fmt.Sprintf("Bearer %s", userToken))
	} else {
		req.Header.Set("Authorization", fmt.Sprintf("Bearer %s", c.ServiceKey))
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Prefer", "return=representation")

	resp, err := c.HTTPClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	if resp.StatusCode >= 400 {
		return nil, fmt.Errorf("supabase error: %s", string(body))
	}

	return body, nil
}

// Delete deletes a record from a Supabase table
func (c *Client) Delete(table string, id string) error {
	return c.DeleteWithToken(table, id, "")
}

// DeleteWithToken deletes a record with an optional user JWT token for RLS
func (c *Client) DeleteWithToken(table string, id string, userToken string) error {
	url := fmt.Sprintf("%s/rest/v1/%s?id=eq.%s", c.URL, table, id)

	req, err := http.NewRequest("DELETE", url, nil)
	if err != nil {
		return err
	}

	req.Header.Set("apikey", c.ServiceKey)

	// Use user token if provided, otherwise use service key
	if userToken != "" {
		req.Header.Set("Authorization", fmt.Sprintf("Bearer %s", userToken))
	} else {
		req.Header.Set("Authorization", fmt.Sprintf("Bearer %s", c.ServiceKey))
	}

	resp, err := c.HTTPClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 400 {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("supabase error: %s", string(body))
	}

	return nil
}

// VerifyToken verifies a JWT token with Supabase
func (c *Client) VerifyToken(token string) (*User, error) {
	url := fmt.Sprintf("%s/auth/v1/user", c.URL)

	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return nil, err
	}

	req.Header.Set("apikey", c.ServiceKey)
	req.Header.Set("Authorization", fmt.Sprintf("Bearer %s", token))

	resp, err := c.HTTPClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to verify token: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response: %w", err)
	}

	if resp.StatusCode >= 400 {
		return nil, fmt.Errorf("token verification failed (status %d): %s", resp.StatusCode, string(body))
	}

	var user User
	if err := json.Unmarshal(body, &user); err != nil {
		return nil, fmt.Errorf("failed to decode user: %w", err)
	}

	return &user, nil
}

// User represents a Supabase user
type User struct {
	ID    string `json:"id"`
	Email string `json:"email"`
}

// Upsert inserts or updates a record in a Supabase table
// onConflict specifies the columns to detect conflicts (e.g., "user_id,date,event_type_id")
func (c *Client) Upsert(table string, data interface{}, onConflict string) ([]byte, error) {
	return c.UpsertWithToken(table, data, onConflict, "")
}

// UpsertWithToken inserts or updates with an optional user JWT token for RLS
func (c *Client) UpsertWithToken(table string, data interface{}, onConflict string, userToken string) ([]byte, error) {
	url := fmt.Sprintf("%s/rest/v1/%s", c.URL, table)

	jsonData, err := json.Marshal(data)
	if err != nil {
		return nil, err
	}

	req, err := http.NewRequest("POST", url, bytes.NewBuffer(jsonData))
	if err != nil {
		return nil, err
	}

	req.Header.Set("apikey", c.ServiceKey)

	// Use user token if provided, otherwise use service key
	if userToken != "" {
		req.Header.Set("Authorization", fmt.Sprintf("Bearer %s", userToken))
	} else {
		req.Header.Set("Authorization", fmt.Sprintf("Bearer %s", c.ServiceKey))
	}

	req.Header.Set("Content-Type", "application/json")
	// Prefer header for upsert - resolution=merge-duplicates will update existing rows
	req.Header.Set("Prefer", "return=representation,resolution=merge-duplicates")

	// Set on_conflict query parameter
	q := req.URL.Query()
	q.Add("on_conflict", onConflict)
	req.URL.RawQuery = q.Encode()

	resp, err := c.HTTPClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	if resp.StatusCode >= 400 {
		return nil, fmt.Errorf("supabase error: %s", string(body))
	}

	return body, nil
}

// DeleteWhere deletes records matching a query
func (c *Client) DeleteWhere(table string, query map[string]interface{}) error {
	return c.DeleteWhereWithToken(table, query, "")
}

// DeleteWhereWithToken deletes records matching a query with an optional user JWT token
func (c *Client) DeleteWhereWithToken(table string, query map[string]interface{}, userToken string) error {
	url := fmt.Sprintf("%s/rest/v1/%s", c.URL, table)

	req, err := http.NewRequest("DELETE", url, nil)
	if err != nil {
		return err
	}

	// Build query parameters
	q := req.URL.Query()
	for key, value := range query {
		q.Add(key, fmt.Sprintf("%v", value))
	}
	req.URL.RawQuery = q.Encode()

	req.Header.Set("apikey", c.ServiceKey)

	// Use user token if provided, otherwise use service key
	if userToken != "" {
		req.Header.Set("Authorization", fmt.Sprintf("Bearer %s", userToken))
	} else {
		req.Header.Set("Authorization", fmt.Sprintf("Bearer %s", c.ServiceKey))
	}

	resp, err := c.HTTPClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 400 {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("supabase error: %s", string(body))
	}

	return nil
}

// UpdateWhere updates records matching a query
func (c *Client) UpdateWhere(table string, query map[string]interface{}, data interface{}) ([]byte, error) {
	return c.UpdateWhereWithToken(table, query, data, "")
}

// UpdateWhereWithToken updates records matching a query with an optional user JWT token
func (c *Client) UpdateWhereWithToken(table string, query map[string]interface{}, data interface{}, userToken string) ([]byte, error) {
	url := fmt.Sprintf("%s/rest/v1/%s", c.URL, table)

	jsonData, err := json.Marshal(data)
	if err != nil {
		return nil, err
	}

	req, err := http.NewRequest("PATCH", url, bytes.NewBuffer(jsonData))
	if err != nil {
		return nil, err
	}

	// Build query parameters
	q := req.URL.Query()
	for key, value := range query {
		q.Add(key, fmt.Sprintf("%v", value))
	}
	req.URL.RawQuery = q.Encode()

	req.Header.Set("apikey", c.ServiceKey)

	// Use user token if provided, otherwise use service key
	if userToken != "" {
		req.Header.Set("Authorization", fmt.Sprintf("Bearer %s", userToken))
	} else {
		req.Header.Set("Authorization", fmt.Sprintf("Bearer %s", c.ServiceKey))
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Prefer", "return=representation")

	resp, err := c.HTTPClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	if resp.StatusCode >= 400 {
		return nil, fmt.Errorf("supabase error: %s", string(body))
	}

	return body, nil
}
