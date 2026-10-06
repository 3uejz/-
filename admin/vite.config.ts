import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// 管理后台构建配置：产物由 Go 服务同源托管于 /admin。
export default defineConfig({
  base: '/admin/',
  plugins: [react()],
  build: {
    outDir: 'dist',
    sourcemap: false,
    // AntD 体积较大，放宽单块告警阈值
    chunkSizeWarningLimit: 1500,
    rollupOptions: {
      output: {
        // 拆分第三方依赖，改善缓存与首屏
        manualChunks: {
          react: ['react', 'react-dom', 'react-router-dom'],
          antd: ['antd', '@ant-design/icons'],
          data: ['@tanstack/react-query', 'zustand'],
        },
      },
    },
  },
  server: {
    host: true,
    port: 5173,
    // 允许平台预览域名访问开发服务器
    allowedHosts: ['.monkeycode-ai.online'],
    // 本地开发时把 /api 反向代理到 Go 后端
    proxy: {
      '/api': {
        target: 'http://localhost:8080',
        changeOrigin: true,
      },
    },
  },
});
