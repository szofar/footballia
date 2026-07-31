package net.footballia.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.SportsSoccer
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import net.footballia.viewmodel.FootballiaViewModel

@Composable
fun LoginScreen(viewModel: FootballiaViewModel) {
    var email by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }

    Box(
        modifier = Modifier.fillMaxSize().background(Color(0xFF0A0A0D)),
        contentAlignment = Alignment.Center
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(40.dp),
            modifier = Modifier.width(440.dp)
        ) {
            // Logo
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Box(
                    modifier = Modifier
                        .size(96.dp)
                        .background(Color(0xFF22C55E).copy(alpha = 0.12f), CircleShape),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(Icons.Default.SportsSoccer, contentDescription = null, tint = Color(0xFF22C55E), modifier = Modifier.size(48.dp))
                }
                Text("FOOTBALLIA", color = Color.White, fontSize = 26.sp, fontWeight = FontWeight.Black, letterSpacing = 6.sp)
                Text("The Football Video Archive", color = Color.White.copy(alpha = 0.35f), fontSize = 13.sp)
            }

            // Form
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                TVTextField(value = email, onValueChange = { email = it }, placeholder = "Email", keyboardType = KeyboardType.Email)
                TVTextField(value = password, onValueChange = { password = it }, placeholder = "Password", isPassword = true)

                viewModel.loginError?.let { err ->
                    Text(err, color = Color(0xFFEF4444), fontSize = 13.sp, modifier = Modifier.padding(horizontal = 4.dp))
                }

                val canSignIn = email.isNotEmpty() && password.isNotEmpty() && !viewModel.isLoading

                Button(
                    onClick = { viewModel.login(email, password) },
                    enabled = canSignIn,
                    modifier = Modifier.fillMaxWidth().height(52.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF22C55E), disabledContainerColor = Color(0xFF22C55E).copy(alpha = 0.4f)),
                    shape = RoundedCornerShape(12.dp)
                ) {
                    if (viewModel.isLoading) {
                        CircularProgressIndicator(modifier = Modifier.size(20.dp), color = Color.Black, strokeWidth = 2.dp)
                    } else {
                        Text("Sign In", color = Color.Black, fontWeight = FontWeight.SemiBold, fontSize = 15.sp)
                    }
                }
            }
        }
    }
}

@Composable
private fun TVTextField(
    value: String,
    onValueChange: (String) -> Unit,
    placeholder: String,
    isPassword: Boolean = false,
    keyboardType: KeyboardType = KeyboardType.Text
) {
    BasicTextField(
        value = value,
        onValueChange = onValueChange,
        singleLine = true,
        visualTransformation = if (isPassword) PasswordVisualTransformation() else VisualTransformation.None,
        keyboardOptions = KeyboardOptions(keyboardType = keyboardType, imeAction = ImeAction.Next),
        textStyle = TextStyle(color = Color.White, fontSize = 14.sp),
        cursorBrush = SolidColor(Color(0xFF22C55E)),
        decorationBox = { inner ->
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(52.dp)
                    .background(Color.White.copy(alpha = 0.05f), RoundedCornerShape(12.dp))
                    .border(1.dp, Color.White.copy(alpha = 0.08f), RoundedCornerShape(12.dp))
                    .padding(horizontal = 16.dp),
                contentAlignment = Alignment.CenterStart
            ) {
                if (value.isEmpty()) Text(placeholder, color = Color.White.copy(alpha = 0.3f), fontSize = 14.sp)
                inner()
            }
        }
    )
}
