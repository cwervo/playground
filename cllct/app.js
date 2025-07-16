const app = document.getElementById('app');

async function main() {
    const SQL = await initSqlJs({ locateFile: file => `https://cdn.jsdelivr.net/npm/sql.js/dist/${file}` });
    const db = new SQL.Database();

    db.run("CREATE TABLE items (id INTEGER PRIMARY KEY, name TEXT, loaned_to TEXT);");

    function render() {
        app.innerHTML = `
            <h1>Cllct</h1>
            <div>
                <input type="text" id="item-name" placeholder="Item name">
                <button id="add-item">Add Item</button>
            </div>
            <div id="item-list"></div>
        `;

        const itemList = document.getElementById('item-list');
        const res = db.exec("SELECT * FROM items");
        if (res.length > 0) {
            const items = res[0].values;
            itemList.innerHTML = items.map(item => `
                <div class="item">
                    <div class="item-name">${item[1]}</div>
                    <div class="item-status">
                        ${item[2] ? `Loaned to: ${item[2]}` : 'Available'}
                    </div>
                    ${item[2] ?
                        `<button class="return-item" data-id="${item[0]}">Return</button>` :
                        `<input type="text" class="loan-to" data-id="${item[0]}" placeholder="Loan to...">
                         <button class="loan-item" data-id="${item[0]}">Loan</button>`
                    }
                </div>
            `).join('');
        } else {
            itemList.innerHTML = '<p>No items in your collection yet.</p>';
        }
    }

    document.addEventListener('click', event => {
        if (event.target.id === 'add-item') {
            const itemName = document.getElementById('item-name').value;
            if (itemName) {
                db.run("INSERT INTO items (name) VALUES (?)", [itemName]);
                render();
            }
        } else if (event.target.classList.contains('loan-item')) {
            const id = event.target.dataset.id;
            const loanTo = document.querySelector(`.loan-to[data-id="${id}"]`).value;
            if (loanTo) {
                db.run("UPDATE items SET loaned_to = ? WHERE id = ?", [loanTo, id]);
                render();
            }
        } else if (event.target.classList.contains('return-item')) {
            const id = event.target.dataset.id;
            db.run("UPDATE items SET loaned_to = NULL WHERE id = ?", [id]);
            render();
        }
    });

    render();
}

main();
