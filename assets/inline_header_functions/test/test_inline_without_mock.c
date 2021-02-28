#include "unity.h"
#include "inline_caller.h"
#include "module_with_inline_func.h"

void setUp(void)
{
}

void tearDown(void)
{
}

void test_should_call_real_inline_func(void)
{
  TEST_ASSERT_EQUAL_INT(1, InlineCaller());
}
