
        import axios from 'axios';
        
        export async function callOlama(ast, key) {
          // Call local OLAMA agent with AST
          // Replace with actual endpoint/config
          const response = await axios.post('http://localhost:11434/api/ast', { ast }, {
            headers: { 'Authorization': `Bearer ${key}` }
          });
          return response.data.suggestions;
        }
    
