import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import App from './App.tsx'
import SafeProvider from '@safe-global/safe-apps-react-sdk'
import ErrorBoundary from './components/ErrorBoundary'

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <SafeProvider>
      <ErrorBoundary>
        <App />
      </ErrorBoundary>
    </SafeProvider>
  </StrictMode>
)
