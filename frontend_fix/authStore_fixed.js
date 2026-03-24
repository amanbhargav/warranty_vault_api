import { create } from 'zustand';
import { authAPI } from '../services/api';

const useAuthStore = create((set, get) => ({
  user: null,
  loading: false,
  initialized: false,
  error: null,
  isAuthenticated: false,
  
  // Initialize auth by checking with backend
  initialize: async () => {
    // Don't reinitialize if already initialized
    if (get().initialized) return;
    
    set({ loading: true });
    try {
      const response = await authAPI.me();
      const user = response.data.user;
      
      set({
        user,
        isAuthenticated: true,
        loading: false,
        initialized: true,
        error: null
      });
    } catch (error) {
      // Not authenticated - this is OK, just means user needs to login
      set({
        user: null,
        isAuthenticated: false,
        loading: false,
        initialized: true,
        error: null
      });
    }
  },
  
  // Sign up
  signup: async (data) => {
    set({ loading: true, error: null });
    try {
      const response = await authAPI.signup(data);
      const { user } = response.data;
      
      set({ 
        user, 
        isAuthenticated: true,
        loading: false,
        error: null 
      });
      return { success: true };
    } catch (error) {
      const message = error.response?.data?.error || 'Signup failed';
      set({ error: message, loading: false });
      return { success: false, error: message };
    }
  },
  
  // Login
  login: async (data) => {
    set({ loading: true, error: null });
    try {
      const response = await authAPI.login(data);
      const { user } = response.data;
      
      set({ 
        user, 
        isAuthenticated: true,
        loading: false,
        error: null 
      });
      return { success: true };
    } catch (error) {
      const message = error.response?.data?.error || 'Login failed';
      set({ error: message, loading: false });
      return { success: false, error: message };
    }
  },
  
  // Logout
  logout: async () => {
    try {
      await authAPI.logout();
    } catch (error) {
      console.error('Logout error:', error);
    }
    
    localStorage.removeItem('user');
    set({ 
      user: null, 
      isAuthenticated: false, 
      error: null,
      initialized: false  // Reset initialized so initialize() can be called again
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
      const response = await authAPI.me();
      const user = response.data.user;
      
      set({ 
        user, 
        isAuthenticated: true,
        initialized: true, 
        loading: false,
        error: null 
      });
      return { success: true };
    } catch (error) {
      const message = error.response?.data?.error || 'Google authentication failed';
      set({ 
        error: message, 
        initialized: true, 
        isAuthenticated: false,
        loading: false 
      });
      return { success: false, error: message };
    }
  },
  
  // Manual set initialized (for login pages)
  setInitialized: () => {
    set({ initialized: true, loading: false });
  },
  
  clearError: () => set({ error: null }),
}));

export default useAuthStore;
