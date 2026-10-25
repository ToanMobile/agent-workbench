#!/usr/bin/env bash
# #261: từ khoá always_human (money) `stripe.` bắt nhầm tên biến (`stripe.material` ở PR #224). Khớp theo ngữ cảnh thật của
# Stripe (import/require, api.stripe.com, khoá sk_live/pk_live, Stripe(...)), giữ nguyên payment_intent/price_id/invoice.create.
# Đi đúng đường của merge gate: github-read (gh giả) → file diff → merge-policy. Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
READ="$ROOT/.claude/bin/super-board-github-read.py"
POLICY="$ROOT/.claude/bin/super-board-merge-policy.py"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-policy-money.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
printf '{"merge_policy":{"default":"auto"}}' > "$TMP/cfg.json"
printf '#!/usr/bin/env bash\ncat "$FAKE_DIFF"\n' > "$TMP/bin/gh"
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH" SB_GITHUB_HALT_FILE="$TMP/halt.json" SB_GITHUB_RETRY_DELAY=0 SB_GITHUB_READ_STRICT=1

# $1 tên, $2 dòng thêm, $3 dòng bị xoá ('' = không có), $4 mong đợi: money | auto
check() {
  python3 - "$TMP/in.diff" "$2" "$3" <<'PY'
import sys
rm = '-' + sys.argv[3] + '\n' if sys.argv[3] else ''
hunk = '@@ -1,1 +1,1 @@\n' + rm if rm else '@@ -1,1 +1,2 @@\n ctx\n'
body = ('diff --git a/app/x.ts b/app/x.ts\nindex 1111111..2222222 100644\n--- a/app/x.ts\n+++ b/app/x.ts\n'
        + hunk + '+' + sys.argv[2] + '\n')
open(sys.argv[1], 'wb').write(body.encode('utf-8'))
PY
  d=0; [ -n "$3" ] && d=1
  printf '{"files":[{"path":"app/x.ts","additions":1,"deletions":%s}],"labels":[],"body":"","additions":1,"deletions":%s,"changedFiles":1}' "$d" "$d" > "$TMP/meta.json"
  rm -f "$TMP/halt.json"
  FAKE_DIFF="$TMP/in.diff" python3 "$READ" --kind diff --meta "$TMP/meta.json" -- pr diff 9 --repo o/r > "$TMP/out.diff" 2>"$TMP/err" \
    || { fail "$1: github-read từ chối ($(tail -1 "$TMP/err"))"; return; }
  plan="$(python3 "$POLICY" --config "$TMP/cfg.json" --meta "$TMP/meta.json" --diff "$TMP/out.diff" 2>&1)"
  case "$4:$plan" in
    money:*'"money"'*) ok "$1: cần người duyệt" ;;
    schema:*'"schema"'*) ok "$1: cần người duyệt" ;;
    auto:*'"human": []'*) ok "$1: vẫn auto" ;;
    *) fail "$1: muốn $4, được: $plan" ;;
  esac
}
check "đối chứng âm: stripe.material (tên biến dải màu, PR #224)" 'stripe.material.depthWrite = false;' '' auto
check "đối chứng âm: biến stripe.color" 'const c = stripe.color;' '' auto
check "import Stripe from 'stripe'" "import Stripe from 'stripe';" '' money
check "require('stripe')" "const s = require('stripe')(key);" '' money
check "python import stripe" 'import stripe' '' money
check "https://api.stripe.com" 'fetch("https://api.stripe.com/v1/charges")' '' money
check "khoá sk_live" 'const k = "sk_live_abc123";' '' money
check "khoá pk_live" 'const k = "pk_live_abc123";' '' money
check "new Stripe(key)" 'const s = new Stripe(process.env.K);' '' money
check "payment_intent vẫn bắt" 'const p = payment_intent.id;' '' money
check "price_id vẫn bắt" 'const p = price_id;' '' money
check "invoice.create vẫn bắt" 'stripeClient.invoice.create({})' '' money
check "đối chứng âm: chỉ dòng '-' có import stripe" 'const a = 1;' "import Stripe from 'stripe';" auto
# Sau #321: file đã import Stripe từ trước, PR chỉ thêm lời gọi SDK (import không nằm trong diff) vẫn phải cần người duyệt.
check "stripe.Charge.create (python, import có sẵn)" 'charge = stripe.Charge.create(amount=100, currency="usd")' '' money
check "stripe.PaymentIntent.create" 'const pi = await stripe.PaymentIntent.create({ amount: 1 });' '' money
check "stripe.api_key = ..." 'stripe.api_key = os.environ["K"]' '' money
check "stripe.refunds.create (node)" 'await stripe.refunds.create({ charge: id });' '' money
check "stripe.checkout.sessions.create" 'const s = await stripe.checkout.sessions.create({ mode: "payment" });' '' money
check "stripe.webhooks.constructEvent" 'const e = stripe.webhooks.constructEvent(body, sig, secret);' '' money
check "đối chứng âm: stripe.mesh.updateMatrix() (three.js)" 'stripe.mesh.updateMatrix();' '' auto
check "đối chứng âm: stripe.position.set(...)" 'stripe.position.set(0, 0, 0);' '' auto
check "đối chứng âm: stripe.geometry.dispose()" 'stripe.geometry.dispose();' '' auto
# Biến thể client/ngôn ngữ khác vẫn là gọi Stripe thật (review aa269cd2).
check "stripeClient.charges.create" 'const c = await stripeClient.charges.create({ amount: 1 });' '' money
check "stripe_client.v1.charges.create" 'c = stripe_client.v1.charges.create(params)' '' money
check "new StripeClient(...)" 'const client = new StripeClient(process.env.K);' '' money
check "ruby Stripe::Charge.create" 'Stripe::Charge.create(amount: 100)' '' money
check "ruby require 'stripe'" "require 'stripe'" '' money
check "php \$stripe->charges->create" '$stripe->charges->create(["amount" => 100]);' '' money
check "php \\Stripe\\Charge::create" '\Stripe\Charge::create(["amount" => 100]);' '' money
check "python create_async" 'charge = await stripe.Charge.create_async(amount=100)' '' money
check "go stripe.Key =" 'stripe.Key = os.Getenv("K")' '' money
check "đối chứng âm: stripeMaterial.dispose()" 'stripeMaterial.dispose();' '' auto
# Dương tính giả kiểu #261 (biến dải màu/bảng kẻ sọc, không phải Stripe): phải auto.
check "đối chứng âm: stripes.delete(...)" 'stripes.delete(id);' '' auto
check "đối chứng âm: stripeCache.delete(...)" 'stripeCache.delete(key);' '' auto
check "đối chứng âm: stripedRows.update(...)" 'stripedRows.update(row);' '' auto
check "đối chứng âm: key={stripe.key}" '<li key={stripe.key}>{stripe.label}</li>' '' auto
check "đối chứng âm: require('striped-table')" "const t = require('striped-table');" '' auto
# Go/Java: import SDK và lời gọi gói paymentintent.
check "go import stripe-go" 'import "github.com/stripe/stripe-go/v76"' '' money
check "go paymentintent.New(" 'pi, err := paymentintent.New(params)' '' money
check "java import com.stripe." 'import com.stripe.model.Charge;' '' money
# Review vòng 4 (25/10): lời gọi tiền vẫn auto-merge (lỗ có từ trước) — Stripe.js, Go params/gói, Java khi import ngoài diff.
check "stripe.js import @stripe/stripe-js" "import { loadStripe } from '@stripe/stripe-js';" '' money
check "stripe.js loadStripe(" 'const stripe = await loadStripe(PK);' '' money
check "stripe.js confirmCardPayment" 'const r = await stripe.confirmCardPayment(secret);' '' money
check "stripe.js redirectToCheckout" 'await stripe.redirectToCheckout({ sessionId });' '' money
check "go &stripe.ChargeParams" 'ch, _ := charge.New(&stripe.ChargeParams{Amount: stripe.Int64(100)})' '' money
check "go refund.New(" 're, _ := refund.New(params)' '' money
check "java PaymentIntent.create (import ngoài diff)" 'PaymentIntent pi = PaymentIntent.create(params);' '' money
check "java Charge.create (import ngoài diff)" 'Charge c = Charge.create(params);' '' money
# Dương tính giả kiểu #261: lời gọi trực tiếp trên biến dải màu, không có đoạn tài nguyên — phải auto.
check "đối chứng âm: stripe.update(color)" 'stripe.update(color);' '' auto
check "đối chứng âm: table.stripe.update(rows)" 'table.stripe.update(rows);' '' auto

echo
[ "$FAILS" -eq 0 ] && { echo "test_merge_policy_money_keywords: PASS"; exit 0; } || { echo "test_merge_policy_money_keywords: FAIL ($FAILS)"; exit 1; }
