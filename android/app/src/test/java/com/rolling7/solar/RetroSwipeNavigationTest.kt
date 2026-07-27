package com.rolling7.solar

import org.junit.Assert.assertEquals
import org.junit.Test

class RetroSwipeNavigationTest {
    @Test
    fun `swipe left opens the next page`() {
        assertEquals(
            RetroTab.ENERGY,
            retroTabAfterSwipe(
                current = RetroTab.DASHBOARD,
                horizontalDistance = -180f,
                verticalDistance = 12f,
                threshold = 72f
            )
        )
    }

    @Test
    fun `swipe right opens the previous page`() {
        assertEquals(
            RetroTab.ENERGY,
            retroTabAfterSwipe(
                current = RetroTab.SYSTEM,
                horizontalDistance = 190f,
                verticalDistance = 20f,
                threshold = 72f
            )
        )
    }

    @Test
    fun `short or mostly vertical gestures do not navigate`() {
        assertEquals(
            RetroTab.SYSTEM,
            retroTabAfterSwipe(
                current = RetroTab.SYSTEM,
                horizontalDistance = -60f,
                verticalDistance = 4f,
                threshold = 72f
            )
        )
        assertEquals(
            RetroTab.SYSTEM,
            retroTabAfterSwipe(
                current = RetroTab.SYSTEM,
                horizontalDistance = -160f,
                verticalDistance = 150f,
                threshold = 72f
            )
        )
    }

    @Test
    fun `swipe stops at first and last page`() {
        assertEquals(
            RetroTab.DASHBOARD,
            retroTabAfterSwipe(
                current = RetroTab.DASHBOARD,
                horizontalDistance = 180f,
                verticalDistance = 0f,
                threshold = 72f
            )
        )
        assertEquals(
            RetroTab.SETTINGS,
            retroTabAfterSwipe(
                current = RetroTab.SETTINGS,
                horizontalDistance = -180f,
                verticalDistance = 0f,
                threshold = 72f
            )
        )
    }
}
