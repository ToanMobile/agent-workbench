#!/bin/bash
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u

DEVKIT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
cd "$D"

mkdir -p src

cat << 'KOTLIN' > src/Test1.kt
import org.junit.Test
class Test1 {
    @Test
    fun testOnlyExistence() {
        val obj = SomeClass()
        assertNotNull(obj)
    }

    @Test
    fun testAssertThatIsNotNull() {
        val obj = SomeClass()
        assertThat(obj).isNotNull()
    }
    
    @Test
    fun testAssertTrueTrue() {
        assertTrue(true)
    }

    @Test
    fun testValidEquals() {
        val obj = SomeClass()
        assertEquals("value", obj.prop)
    }

    @Test
    fun testAssertThrows() {
        assertThrows<Exception> {
            doSomething()
        }
    }

    @Test
    fun testVerify() {
        verify(mock).method()
    }

    @Test
    fun testAssertTrueExpression() {
        assertTrue(obj.isValid())
    }

    @Test
    fun testFactoryVar() {
        val r = Factory.load()
        assertNotNull(r)
    }

    @Test
    fun testFactoryCall() {
        assertNotNull(Factory.load("x"))
    }

    @Test
    fun testSingleton() {
        assertNotNull(VoiceAudioFocusManager)
    }

    @Test
    fun testThingVar() {
        val o = Thing()
        assertNotNull(o)
    }
    @Test
    fun testConstructorMethodChain() {
        val user = UserRepository(db).findById(42)
        assertNotNull(user)
    }

    @Test
    fun testConstructorDirect() {
        val repo = UserRepository(db)
        assertNotNull(repo)
    }

    @Test
    fun testConstructorNested() {
        val u = Foo(Bar())
        assertNotNull(u)
    }

    @Test
    fun testMsgDotProperty() {
        assertNotNull("msg", reader.model)
    }

    @Test
    fun testMsgFunctionCall() {
        assertNotNull("msg", Holder.getContextOrNull())
    }

    @Test
    fun testMsgThingVar2() {
        val o = Thing()
        assertNotNull("msg", o)
    }

    @Test
    fun testMsgAssignedProperty() {
        val m = reader.model
        assertNotNull("msg", m)
    }

    @Test
    fun testMsgThingVarKotlinTest() {
        val value = Thing()
        assertNotNull(value, "msg")
    }

    @Test
    fun testReassignedVar() {
        var x = Foo()
        x = repo.load(id)
        assertNotNull(x)
    }
}
KOTLIN

cat << 'JAVA' > src/Test2.java
import org.junit.Test;
public class Test2 {
    @Test
    public void testOnlyExistenceJava() {
        Object obj = new Object();
        Assert.IsNotNull(obj);
    }
}
JAVA

LINT_SCRIPT="$DEVKIT_ROOT/scripts/linters/assertion_lint.py"

OUTPUT=$(python3 -I "$LINT_SCRIPT" src/Test1.kt src/Test2.java 2>&1 || true)

ERRORS=0

function expect_flagged() {
    local file="$1"
    local line="$2"
    if echo "$OUTPUT" | grep -q "$file:$line:"; then
        echo "OK: $file:$line was flagged"
    else
        echo "FAIL: $file:$line was NOT flagged"
        ERRORS=$((ERRORS+1))
    fi
}

function expect_not_flagged() {
    local file="$1"
    local line="$2"
    if echo "$OUTPUT" | grep -q "$file:$line:"; then
        echo "FAIL: $file:$line was flagged"
        ERRORS=$((ERRORS+1))
    else
        echo "OK: $file:$line was NOT flagged"
    fi
}

# Line numbers where @Test is
expect_flagged "src/Test1.kt" "3"   # testOnlyExistence
expect_flagged "src/Test1.kt" "9"   # testAssertThatIsNotNull
expect_flagged "src/Test1.kt" "15"  # testAssertTrueTrue
expect_flagged "src/Test2.java" "3" # testOnlyExistenceJava
expect_not_flagged "src/Test1.kt" "43" # testFactoryVar (i)
expect_not_flagged "src/Test1.kt" "49" # testFactoryCall (ii)
expect_flagged "src/Test1.kt" "54" # testSingleton (iii)
expect_flagged "src/Test1.kt" "59" # testThingVar (iv)

expect_not_flagged "src/Test1.kt" "64" # testConstructorMethodChain
expect_flagged "src/Test1.kt" "70" # testConstructorDirect
expect_not_flagged "src/Test1.kt" "76" # testConstructorNested

expect_not_flagged "src/Test1.kt" "82" # testMsgDotProperty
expect_not_flagged "src/Test1.kt" "87" # testMsgFunctionCall
expect_flagged "src/Test1.kt" "92" # testMsgThingVar2
expect_not_flagged "src/Test1.kt" "98" # testMsgAssignedProperty
expect_flagged "src/Test1.kt" "104" # testMsgThingVarKotlinTest
expect_not_flagged "src/Test1.kt" "110" # testReassignedVar

expect_not_flagged "src/Test1.kt" "20" # testValidEquals
expect_not_flagged "src/Test1.kt" "26" # testAssertThrows
expect_not_flagged "src/Test1.kt" "33" # testVerify
expect_not_flagged "src/Test1.kt" "38" # testAssertTrueExpression

if [ $ERRORS -gt 0 ]; then
    echo "$ERRORS FAILED"
    echo "Output was:"
    echo "$OUTPUT"
    exit 1
else
    echo "ALL OK"
    exit 0
fi
