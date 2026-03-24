/**
 * Login Component - User authentication form
 * 
 * Features:
 * - Email/password login
 * - Cookie-based authentication (automatic)
 * - Session expiry message display
 * - Redirect after successful login
 * - Google OAuth login option
 */

import React, { useState, useEffect } from 'react';
import { Link, useNavigate, useLocation, Navigate } from 'react-router-dom';
import { useAuth } from '../contexts/AuthContext';

export function LoginPage() {
  const navigate = useNavigate();
  const location = useLocation();
  const { login, isAuthenticated, error, clearError, sessionExpired } = useAuth();
  
  // Form state
  const [formData, setFormData] = useState({
    email: '',
    password: ''
  });
  
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [formError, setFormError] = useState('');
  
  // Get redirect location from state
  const from = location.state?.from?.pathname || '/';
  const sessionExpiredMessage = location.state?.message;
  
  // Redirect if already authenticated
  if (isAuthenticated) {
    return <Navigate to={from} replace />;
  }
  
  // Handle input change
  const handleChange = (e) => {
    const { name, value } = e.target;
    setFormData(prev => ({
      ...prev,
      [name]: value
    }));
    // Clear errors when user types
    setFormError('');
    clearError();
  };
  
  // Handle form submission
  const handleSubmit = async (e) => {
    e.preventDefault();
    
    // Validation
    if (!formData.email || !formData.password) {
      setFormError('Please fill in all fields');
      return;
    }
    
    if (!formData.email.includes('@')) {
      setFormError('Please enter a valid email address');
      return;
    }
    
    setIsSubmitting(true);
    setFormError('');
    
    // Attempt login
    const result = await login(formData.email, formData.password);
    
    if (!result.success) {
      setFormError(result.error || 'Login failed');
    }
    
    setIsSubmitting(false);
  };
  
  // Handle Google OAuth login
  const handleGoogleLogin = () => {
    // Redirect to backend OAuth endpoint
    window.location.href = `${import.meta.env.VITE_API_URL || ''}/auth/google`;
  };
  
  return (
    <div className="login-page">
      <div className="login-container">
        <div className="login-header">
          <h1>Welcome Back</h1>
          <p>Sign in to your account to continue</p>
        </div>
        
        {/* Session Expired Alert */}
        {sessionExpired && (
          <div className="alert alert-warning alert-session-expired">
            <span className="alert-icon">⚠️</span>
            <span>{sessionExpiredMessage || 'Session expired due to inactivity'}</span>
          </div>
        )}
        
        {/* Error Display */}
        {formError && !sessionExpired && (
          <div className="alert alert-error">
            <span className="alert-icon">❌</span>
            <span>{formError}</span>
          </div>
        )}
        
        {/* Login Form */}
        <form onSubmit={handleSubmit} className="login-form" noValidate>
          <div className="form-group">
            <label htmlFor="email">Email Address</label>
            <input
              type="email"
              id="email"
              name="email"
              value={formData.email}
              onChange={handleChange}
              placeholder="you@example.com"
              autoComplete="email"
              disabled={isSubmitting}
              required
            />
          </div>
          
          <div className="form-group">
            <label htmlFor="password">Password</label>
            <input
              type="password"
              id="password"
              name="password"
              value={formData.password}
              onChange={handleChange}
              placeholder="Enter your password"
              autoComplete="current-password"
              disabled={isSubmitting}
              required
            />
          </div>
          
          <div className="form-actions">
            <Link to="/forgot-password" className="forgot-password-link">
              Forgot password?
            </Link>
          </div>
          
          <button 
            type="submit" 
            className="btn btn-primary btn-login"
            disabled={isSubmitting}
          >
            {isSubmitting ? 'Signing in...' : 'Sign In'}
          </button>
        </form>
        
        {/* Divider */}
        <div className="divider">
          <span>OR</span>
        </div>
        
        {/* Google OAuth Button */}
        <button 
          onClick={handleGoogleLogin}
          className="btn btn-google btn-login-google"
          disabled={isSubmitting}
        >
          <svg className="google-icon" viewBox="0 0 24 24">
            <path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"/>
            <path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"/>
            <path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"/>
            <path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"/>
          </svg>
          Continue with Google
        </button>
        
        {/* Signup Link */}
        <div className="login-footer">
          <p>
            Don't have an account?{' '}
            <Link to="/signup" className="signup-link">
              Sign up
            </Link>
          </p>
        </div>
      </div>
    </div>
  );
}

export default LoginPage;
