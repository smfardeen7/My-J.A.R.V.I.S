import React from 'react'
import ReactDOM from 'react-dom/client'
import App from './App'
import './demo.css'
import DesktopApp from './desktop/DesktopApp'
import { isDesktop } from './desktop/bridge'

ReactDOM.createRoot(document.getElementById('root')!).render(<React.StrictMode>{isDesktop() ? <DesktopApp/> : <App/>}</React.StrictMode>)
