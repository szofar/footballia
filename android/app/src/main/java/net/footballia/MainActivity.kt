package net.footballia

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import net.footballia.dev.DevCredentials
import net.footballia.ui.RootScreen
import net.footballia.ui.theme.FootballiaTheme
import net.footballia.viewmodel.FootballiaViewModel

class MainActivity : ComponentActivity() {
    private val viewModel: FootballiaViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        viewModel.start(DevCredentials.load(this))
        setContent {
            FootballiaTheme {
                RootScreen(viewModel)
            }
        }
    }
}
