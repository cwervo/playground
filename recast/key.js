
        import dotenv from 'dotenv';
        dotenv.config();
        
        export function getKey() {
          return process.env.OLAMA_API_KEY || '';
        }
    
