const state = {
  products: [],
  category: 'All',
  search: '',
  cartCount: 0
};

const productGrid = document.querySelector('#product-grid');
const categories = document.querySelector('#categories');
const searchInput = document.querySelector('#product-search');
const cartCount = document.querySelector('.cart-count');
const catalogNotice = document.querySelector('#catalog-notice');

function renderCategories() {
  const values = ['All', ...new Set(state.products.map(product => product.category))];
  categories.innerHTML = values.map(category => `
    <button type="button" class="${state.category === category ? 'active' : ''}" data-category="${category}">
      ${category}
    </button>
  `).join('');
}

function renderProducts() {
  const query = state.search.toLowerCase();
  const visible = state.products.filter(product => {
    const matchesCategory = state.category === 'All' || product.category === state.category;
    const matchesSearch = !query || `${product.name} ${product.category}`.toLowerCase().includes(query);
    return matchesCategory && matchesSearch;
  });

  productGrid.innerHTML = visible.length ? visible.map(product => `
    <article class="product-card">
      <div class="product-visual"><span class="product-badge">${product.badge}</span></div>
      <div class="product-body">
        <span class="product-category">${product.category}</span>
        <h3>${product.name}</h3>
        <span class="availability">${product.availability}</span>
        <div class="product-footer">
          <strong>$${Number(product.price).toFixed(2)}</strong>
          <button type="button" class="add-button" data-product-id="${product.id}">Add</button>
        </div>
      </div>
    </article>
  `).join('') : '<div class="loading-card">No products match your search.</div>';
}

async function loadCatalog() {
  try {
    const response = await fetch('/api/catalog');
    if (!response.ok) throw new Error(`Catalog returned ${response.status}`);
    const data = await response.json();
    state.products = data.products;
    renderCategories();
    renderProducts();
  } catch (error) {
    productGrid.innerHTML = '<div class="loading-card">The pharmacy catalog is temporarily unavailable.</div>';
    catalogNotice.textContent = 'Our care team is working to restore the catalog.';
    catalogNotice.classList.remove('hidden');
  }
}

categories.addEventListener('click', event => {
  const button = event.target.closest('[data-category]');
  if (!button) return;
  state.category = button.dataset.category;
  renderCategories();
  renderProducts();
});

searchInput.addEventListener('input', event => {
  state.search = event.target.value.trim();
  renderProducts();
});

productGrid.addEventListener('click', event => {
  const button = event.target.closest('[data-product-id]');
  if (!button) return;
  state.cartCount += 1;
  cartCount.textContent = String(state.cartCount);
  button.textContent = 'Added';
  setTimeout(() => { button.textContent = 'Add'; }, 900);
});

document.querySelector('#check-benefits').addEventListener('click', async () => {
  const card = document.querySelector('#coverage-card');
  const memberId = document.querySelector('#member-id').value.trim();
  card.innerHTML = '<span class="status-chip">Checking securely</span><h3>Connecting to your plan</h3><p>This normally takes only a moment.</p>';

  try {
    const response = await fetch(`/api/benefits/${encodeURIComponent(memberId)}`);
    const body = await response.json();
    if (!response.ok) throw new Error(body.detail || 'Benefits request failed');

    card.innerHTML = `
      <span class="status-chip status-positive">${body.eligible ? 'Coverage active' : 'Review required'}</span>
      <h3>${body.plan}</h3>
      <p>Your benefits are connected and ready for eligible prescription purchases.</p>
      <div class="coverage-details">
        <div><small>Member</small><strong>${body.memberId}</strong></div>
        <div><small>Rx group</small><strong>${body.rxGroup}</strong></div>
        <div><small>Expected copay</small><strong>$${Number(body.copay).toFixed(2)}</strong></div>
        <div><small>Eligibility source</small><strong>Connected plan</strong></div>
      </div>`;
  } catch (error) {
    card.innerHTML = `
      <span class="status-chip status-error">Temporarily unavailable</span>
      <h3>We could not confirm coverage</h3>
      <p>${error.message}. Your prescriptions remain safe; please try again shortly.</p>`;
  }
});

async function loadServiceStatus(path, titleId, detailId, indicatorId, noun) {
  const title = document.querySelector(`#${titleId}`);
  const detail = document.querySelector(`#${detailId}`);
  const indicator = document.querySelector(`#${indicatorId}`);

  try {
    const response = await fetch(path);
    const body = await response.json();
    if (!response.ok) throw new Error(`${noun} service returned ${response.status}`);
    const entries = body.orders || body.payments || [];
    title.textContent = entries.length ? `${entries.length} recent ${noun.toLowerCase()}` : `No recent ${noun.toLowerCase()}`;
    detail.textContent = entries.length ? 'Connected services are responding normally.' : 'You are all caught up.';
    indicator.classList.add('healthy');
  } catch (error) {
    title.textContent = `${noun} status unavailable`;
    detail.textContent = 'We are reconnecting to this service.';
    indicator.classList.add('unhealthy');
  }
}

document.querySelector('#pay-prescription').addEventListener('click', async event => {
  const button = event.currentTarget;
  const title = document.querySelector('#payment-title');
  const detail = document.querySelector('#payment-detail');
  const indicator = document.querySelector('#payment-indicator');

  button.disabled = true;
  button.textContent = 'Verifying benefits...';
  title.textContent = 'Processing prescription payment';
  detail.textContent = 'Confirming eligibility and calculating your copay.';
  indicator.classList.remove('healthy', 'unhealthy');

  try {
    const response = await fetch('/api/payments/process', { method: 'POST' });
    const body = await response.json();
    if (!response.ok) {
      throw new Error(body.detail || 'Payment could not be processed');
    }

    title.textContent = `Payment complete · $${Number(body.amount).toFixed(2)}`;
    detail.textContent = `${body.plan} benefits verified. Confirmation ${body.transactionId.slice(0, 8).toUpperCase()}.`;
    button.textContent = 'Paid';
    indicator.classList.add('healthy');
  } catch (error) {
    title.textContent = 'Payment could not be processed';
    detail.textContent = `${error.message} No charge was made.`;
    button.textContent = 'Try Review & pay again';
    button.disabled = false;
    indicator.classList.add('unhealthy');
  }
});

loadCatalog();
loadServiceStatus('/api/orders', 'order-title', 'order-detail', 'order-indicator', 'Orders');
