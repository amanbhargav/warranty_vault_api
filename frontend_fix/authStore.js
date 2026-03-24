import { create } from 'zustand';
import { authAPI } from '../services/api';

const useAuthStore = create((set, get) => ({
  user: null,
  // Cookie-based auth: don't store token in localStorage
  // Cookies are automatically sent by axios with withCredentials: true
  loading: false,
  initialized: false,
  error: null,
  sessionExpired: false,
  
  // Initialize auth by checking with backend
  initialize: async () => {
    set({ loading: true });
    try {
      // Try to get current user - cookie will be sent automatically
      const response = await authAPI.me();
      const user = response.data.user;
      
      set({
        user,
        loading: false,
        initialized: true
      });
    } catch (error) {
      // Not authenticated or session expired
      set({
        user: null,
        loading: false,
        initialized: true
      });
    }
  },
  
  // Sign up - cookie will be set automatically by backend
  signup: async (data) => {
    set({ loading: true, error: null, sessionExpired: false });
    try {
      const response = await authAPI.signup(data);
      const { user } = response.data;
      
      // Don't store token - cookie is set automatically
      set({
        user,
        loading: false
      });
      
      return { success: true };
    } catch (error) {
      const message = error.response?.data?.error || 'Signup failed';
      set({ error: message, loading: false });
      return { success: false, error: message };
    }
  },
  
  // Login - cookie will be set automatically by backend
  login: async (data) => {
    set({ loading: true, error: null, sessionExpired: false });
    try {
      console.log('[Auth] Attempting login for:', data.email);
      const response = await authAPI.login(data);
      const { user, message } = response.data;
      
      console.log('[Auth] Login successful:', user);
      
      // Don't store token - cookie is set automatically
      set({
        user,
        loading: false
      });
      
      return { success: true };
    } catch (error) {
      console.error('[Auth] Login failed:', error);
      const message = error.response?.data?.error || 'Login failed';
      set({ error: message, loading: false });
      return { success: false, error: message };
    }
  },
  
  // Logout - clear cookie via backend
  logout: async () => {
    try {
      await authAPI.logout();
    } catch (error) {
      console.error('[Auth] Logout error:', error);
    }
    
    // Clear local state
    localStorage.removeItem('user');
    
    set({
      user: null,
      error: null,
      sessionExpired: false
    });
  },
  
  // Update user
  updateUser: (userData) => {
    const updatedUser = { ...get().user, ...userData };
    localStorage.setItem('user', JSON.stringify(updatedUser));
    set({ user: updatedUser });
  },
  
  // Handle Google OAuth callback
  handleOAuthCallback: async () => {
    set({ loading: true, error: null });
    
    try {
      // Cookie should already be set by redirect
      // Just fetch the user data
      const response = await authAPI.me();
      const user = response.data.user;
      
      set({
        user,
        initialized: true,
        loading: false
      });
      
      return { success: true };
    } catch (error) {
      const message = error.response?.data?.error || 'Google authentication failed';
      set({
        error: message,
        initialized: true,
        loading: false
      });
      
      return { success: false, error: message };
    }
  },
  
  // Set session expired flag
  setSessionExpired: (expired, message = null) => {
    set({
      sessionExpired: expired,
      error: message || (expired ? 'Session expired due to inactivity' : null)
    });
  },
  
  // Clear error
  clearError: () => set({ error: null }),
}));

export default useAuthStore;
