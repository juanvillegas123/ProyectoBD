import csv
import random

nombres_base = ["Carlos", "Ana", "Luis", "Maria", "Jorge", "Lucia", "Pedro", "Sofia", "Miguel", "Valeria"]
apellidos_base = ["Perez", "Gomez", "Flores", "Rojas", "Mamani", "Quispe", "Fernandez", "Lopez", "Condori", "Vargas"]
calles = ["Av. Arce", "Calle Sucre", "El Prado", "Av. 6 de Agosto", "Calle Potosí", "Plaza Principal"]

# Asegúrate de guardarlo en tu carpeta data del proyecto
with open("padron_contribuyentes.csv", mode="w", newline="", encoding="utf-8") as f:
    writer = csv.writer(f)
    # Encabezados exactos requeridos por la tabla
    writer.writerow(["ci_nit", "nombres_razon_social", "tipo_persona", "telefono", "email", "direccion_fiscal", "estado"])
    
    for i in range(1, 1200):  # Genera ~1,200 registros
        ci = f"{random.randint(1000000, 9999999)}LP"
        nombre = f"{random.choice(nombres_base)} {random.choice(apellidos_base)} {random.choice(apellidos_base)}"
        tipo = "N"
        tel = f"7{random.randint(6000000, 7999999)}"
        email = f"contribuyente{i}@mail.com"
        direccion = f"{random.choice(calles)} # {random.randint(10, 500)}"
        estado = random.choices(["Activo", "Inactivo", "Observado"], weights=[80, 15, 5])[0]
        
        writer.writerow([ci, nombre, tipo, tel, email, direccion, estado])

print("¡Archivo padron_contribuyentes.csv generado con éxito!")