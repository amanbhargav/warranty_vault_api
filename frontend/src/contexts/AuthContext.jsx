/**
 * AuthContext - React Context for authentication state management
 *
 * Provides:
 * - User authentication state
 * - Login/logout functions
 * - Auto-logout on idle timeout
 * - 401 response handling (with retry logic)
 * - Session expiry detection
 */

import React, { createContext, useContext, useState, useEffect, useCallback, useMemo } from 'react';
import { useNavigate, useLocation } from 'react-router-dom';
import useIdleTimeout from '../hooks/useIdleTimeout';
import api from '../utils/api';

// Auth context
const AuthContext = createContext(null);

// Session expiry message
const SESSION_EXPIRED_MESSAGE = 'Session expired due to inactivity';

/**
 * AuthProvider - Wraps application with authentication context
 */
export function AuthProvider({ children }) {
  const navigate = useNavigate();
  const location = useLocation();

  // User state
  const [user, setUser] = useState(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState(null);
  const [sessionExpired, setSessionExpired] = useState(false);

  // Handle session expired
  const handleSessionExpired = useCallback((message = SESSION_EXPIRED_MESSAGE) => {
    console.log('[Auth] Session expired:', message);
    
    setUser(null);
    setSessionExpired(true);
    setError(message);

    // Clear any client-side session storage (if used for non-sensitive data)
    localStorage.removeItem('user_preferences');

    // Redirect to login
    navigate('/login', {
      state: {
        from: location,
        sessionExpired: true,
        message: message
      },
      replace: true
    });
  }, [navigate, location]);

  // Listen for session expired events from API interceptor
  useEffect(() => {
    const handleSessionExpiredEvent = (event) => {
      const message = event.detail?.message || SESSION_EXPIRED_MESSAGE;
      handleSessionExpired(message);
    };

    window.addEventListener('auth:sessionExpired', handleSessionExpiredEvent);

    return () => {
      window.removeEventListener('auth:sessionExpired', handleSessionExpiredEvent);
    };
  }, [handleSessionExpired]);

  // Handle idle timeout
  const handleIdle = useCallback(() => {
    handleSessionExpired(SESSION_EXPIRED_MESSAGE);
  }, [handleSessionExpired]);

  // Use idle timeout hook (2 hours)
  const { isIdle } = useIdleTimeout(handleIdle, 2 * 60 * 60 * 1000);

  // Login function
  const login = useCallback(async (email, password) => {
    try {
      setError(null);
      setSessionExpired(false);

      console.log('[Auth] Attempting login for:', email);

      const response = await api.post('/api/v1/auth/login', {
        email,
        password
      });

      console.log('[Auth] Login successful:', response.data.user);
      
      setUser(response.data.user);
      
      // Verify cookie was set (debug)
      if (import.meta.env.DEV) {
        console.log('[Auth] Cookie should be set - check Application tab');
      }
      
      navigate('/', { replace: true });

      return { success: true };
    } catch (err) {
      console.error('[Auth] Login error:', err);
      const errorMessage = err.response?.data?.error || 'Login failed';
      setError(errorMessage);
      return { 
        success: false, 
        error: errorMessage 
      };
    }
  }, [navigate]);

  // Signup function
  const signup = useCallback(async (userData) => {
    try {
      setError(null);

      console.log('[Auth] Attempting signup for:', userData.email);

      const response = await api.post('/api/v1/auth/signup', userData);

      console.log('[Auth] Signup successful:', response.data.user);
      
      setUser(response.data.user);
      navigate('/', { replace: true });

      return { success: true };
    } catch (err) {
      console.error('[Auth] Signup error:', err);
      const errorMessage = err.response?.data?.error || 'Signup failed';
      setError(errorMessage);
      return { 
        success: false, 
        error: errorMessage 
      };
    }
  }, [navigate]);

  // Logout function
  const logout = useCallback(async () => {
    try {
      // Call logout endpoint to clear cookie
      await api.post('/api/v1/auth/logout');
      console.log('[Auth] Logout successful');
    } catch (err) {
      // Ignore errors, still clear local state
      console.warn('[Auth] Logout API call failed:', err);
    } finally {
      setUser(null);
      navigate('/login', { replace: true });
    }
  }, [navigate]);

  // Check if user is authenticated (on mount)
  useEffect(() => {
    const checkAuth = async () => {
      try {
        console.log('[Auth] Checking authentication status...');
        const response = await api.get('/api/v1/auth/me');
        setUser(response.data.user);
        console.log('[Auth] User authenticated:', response.data.user);
      } catch (err) {
        // Not authenticated, clear user
        console.log('[Auth] Not authenticated or session expired');
        setUser(null);
      } finally {
        setIsLoading(false);
      }
    };

    checkAuth();
  }, []);

  // Clear session expired flag when navigating to login
  useEffect(() => {
    if (location.pathname === '/login') {
      setSessionExpired(false);
    }
  }, [location.pathname]);

  // Context value
  const contextValue = useMemo(() => ({
    user,
    isLoading,
    isAuthenticated: !!user,
    error,
    sessionExpired,
    login,
    signup,
    logout,
    clearError: () => setError(null),
    clearSessionExpired: () => setSessionExpired(false)
  }), [user, isLoading, error, sessionExpired, login, signup, logout]);

  return (
    <AuthContext.Provider value={contextValue}>
      {children}
    </AuthContext.Provider>
  );
}

/**
 * useAuth - Hook to access authentication context
 * @returns {Object} Authentication context value
 */
export function useAuth() {
  const context = useContext(AuthContext);

  if (!context) {
    throw new Error('useAuth must be used within an AuthProvider');
  }

  return context;
}

/**
 * RequireAuth - HOC to protect routes requiring authentication
 */
export function RequireAuth({ children }) {
  const { isAuthenticated, isLoading } = useAuth();
  const location = useLocation();

  if (isLoading) {
    return (
      <div className="loading-container">
        <div className="loading-spinner">Loading...</div>
      </div>
    );
  }

  if (!isAuthenticated) {
    // Redirect to login, saving the location they were trying to access
    return <Navigate to="/login" state={{ from: location }} replace />;
  }

  return children;
}

export default AuthContext;
