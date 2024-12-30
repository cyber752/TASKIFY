let ws;
let todos = [];

function connectWebSocket() {
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    const wsUrl = `${protocol}//${window.location.host}`;
    
    ws = new WebSocket(wsUrl);
    
    ws.onmessage = (event) => {
        const message = JSON.parse(event.data);
        
        if (message.type === 'init' || message.type === 'update') {
            todos = message.data;
            renderTodos();
        }
    };

    ws.onclose = () => {
        setTimeout(connectWebSocket, 1000);
    };
}

function renderTodos() {
    const todoList = document.getElementById('todos');
    todoList.innerHTML = todos.map(todo => `
        <div class="todo-item ${todo.completed ? 'completed' : ''}">
            <input type="checkbox" 
                   ${todo.completed ? 'checked' : ''} 
                   onchange="toggleTodo(${todo.id})">
            <span class="todo-text">${todo.text}</span>
            <span class="todo-date">${new Date(todo.date).toLocaleDateString()}</span>
        </div>
    `).join('');
}

function toggleTodo(id) {
    const todo = todos.find(t => t.id === id);
    if (todo) {
        todo.completed = !todo.completed;
        ws.send(JSON.stringify({
            type: 'update',
            data: todos
        }));
    }
}

connectWebSocket();