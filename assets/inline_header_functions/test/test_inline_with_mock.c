#include "unity.h"
#include "inline_caller.h"
#include "mock_module_with_inline_func.h"

void setUp(void)
{
}

void tearDown(void)
{
}

void test_should_call_mockable_inline(void)
{
  inline_header_function_ExpectAndReturn(2);
  TEST_ASSERT_EQUAL_INT(2, InlineCaller());
}
