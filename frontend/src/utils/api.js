/**
 * API Client - Axios instance configured for cookie-based authentication
 *
 * Configuration:
 * - withCredentials: true (sends cookies with every request)
 * - Base URL from environment
 * - Request/response interceptors
 */

import axios from 'axios';

// Get base URL from environment
const API_BASE_URL = import.meta.env.VITE_API_URL || 'http://localhost:3000';

// Track if we're currently refreshing to avoid infinite loops
let isRefreshing = false;
let failedQueue = [];

const processQueue = (error, token = null) => {
  failedQueue.forEach(prom => {
    if (error) {
      prom.reject(error);
    } else {
      prom.resolve(token);
    }
  });

  failedQueue = [];
};

// Create axios instance
const api = axios.create({
  baseURL: API_BASE_URL,
  headers: {
    'Content-Type': 'application/json',
    'Accept': 'application/json'
  },
  // CRITICAL: Send cookies with every request
  withCredentials: true,
  // Allow cross-origin requests with credentials
  xsrfCookieName: false, // We're using custom cookie auth, not XSRF
  xsrfHeaderName: false
});

// Request interceptor - add any additional headers if needed
api.interceptors.request.use(
  config => {
    // Log outgoing requests (debug)
    if (import.meta.env.DEV) {
      console.log(`[API] ${config.method?.toUpperCase()} ${config.url}`);
    }
    return config;
  },
  error => {
    console.error('[API] Request error:', error);
    return Promise.reject(error);
  }
);

// Response interceptor - handle common errors
api.interceptors.response.use(
  response => response,
  error => {
    const originalRequest = error.config;

    // Log errors (debug)
    if (import.meta.env.DEV) {
      console.error(`[API] ${error.config?.method?.toUpperCase()} ${error.config?.url} - ${error.response?.status || 'Network Error'}`);
    }

    // If error is 401 and we haven't already retried
    if (error.response?.status === 401 && !originalRequest._retry) {
      // Don't trigger logout for login/signup requests
      const isAuthRequest = originalRequest.url?.includes('/auth/login') ||
                           originalRequest.url?.includes('/auth/signup');

      if (isAuthRequest) {
        // Let the login component handle the error
        return Promise.reject(error);
      }

      // Mark as retried to avoid infinite loops
      originalRequest._retry = true;

      // Check if this is the first 401 (might be token refresh issue)
      // Try the request again - the cookie should be automatically sent
      // If it fails again, then we know the session is truly expired
      return api(originalRequest)
        .then(response => {
          // Success on retry - session was valid
          return response;
        })
        .catch(retryError => {
          // Second failure - session is truly expired
          // Dispatch custom event for AuthContext to handle
          window.dispatchEvent(new CustomEvent('auth:sessionExpired', {
            detail: { message: 'Session expired due to inactivity' }
          }));
          return Promise.reject(retryError);
        });
    }

    // 500 Server Error
    if (error.response?.status === 500) {
      console.error('[API] Server error occurred');
    }

    return Promise.reject(error);
  }
);

export default api;
