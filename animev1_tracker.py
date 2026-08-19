import re
import sys
import time
from dataclasses import dataclass, asdict
from typing import List, Optional
from urllib.parse import urlparse

# Automatización de Navegador y Base de Datos
import firebase_admin
from firebase_admin import credentials, firestore
from playwright.sync_api import sync_playwright
from bs4 import BeautifulSoup

BASE_URL = "https://animev1.com"

# --- CONFIGURACIÓN DE FIREBASE --------------------------------------------
# Apunta al archivo .json de credenciales que subiste a tu GitHub
SERVICE_ACCOUNT_KEY_PATH = "firebase_secret.json" 
COLECCION_EPISODIOS = "tracker_episodios"

@dataclass
class EpisodioReciente:
    id_slug: str
    titulo: str
    episodio: Optional[int]
    imagen_url: Optional[str]
    capitulo_url: str
    links_referencia: List[str] # Los videos viajan protegidos bajo este nombre

# --- UTILIDADES DE PARSEO Y EXTRACCIÓN --------------------------------------

def _extraer_numero_episodio(texto: str, url: str) -> Optional[int]:
    match = re.search(r"epi\w*\s*(\d+)", texto, re.IGNORECASE)
    if match:
        return int(match.group(1))
    match = re.search(r"-(\d+)/?$", url)
    if match:
        return int(match.group(1))
    return None

def generar_id_desde_url(url: str) -> str:
    ruta = urlparse(url).path.rstrip("/")
    slug = ruta.split("/")[-1]
    return slug or ruta.replace("/", "_")

def extraer_reproductores_reales(html_contenido: str) -> List[str]:
    """
    Inyección manual: Extrae las URLs reales de los servidores de video 
    (Mega, Streamtape, etc.) desde las pestañas/iframes del capítulo.
    """
    links_video = []
    sub_soup = BeautifulSoup(html_contenido, 'html.parser')
    
    # Localiza todas las etiquetas iframe del reproductor
    iframes = sub_soup.find_all('iframe')
    for iframe in iframes:
        src = iframe.get('src')
        if src:
            # Filtro básico anti-anuncios obvios
            if "ads" not in src and "pop" not in src and "creative" not in src:
                if src.startswith("//"):
                    src = "https:" + src
                links_video.append(src)
                
    return links_video

# --- CONEXIÓN A FIREBASE ----------------------------------------------------

def inicializar_firestore(ruta_credenciales: str) -> firestore.Client:
    cred = credentials.Certificate(ruta_credenciales)
    firebase_admin.initialize_app(cred)
    return firestore.client()

def subir_a_firestore(db: firestore.Client, episodios: List[EpisodioReciente]) -> None:
    coleccion = db.collection(COLECCION_EPISODIOS)
    nuevos = 0
    ya_existian = 0

    for episodio in episodios:
        doc_ref = coleccion.document(episodio.id_slug)

        # Evita duplicar capítulos ya procesados en Firestore
        if doc_ref.get().exists:
            ya_existian += 1
            continue

        doc_ref.set(asdict(episodio))
        nuevos += 1
        print(f"[OK] Subido: {episodio.titulo} (Episodio {episodio.episodio})")

    print(f"\nResumen: {nuevos} nuevos agregados, {ya_existian} ya existían en Firestore.")

# --- FLUJO PRINCIPAL EJECUTADO POR GITHUB ACTIONS ---------------------------

def ejecutar_extractor():
    print("[INFO] Lanzando navegador invisible para pasar Cloudflare...")
    
    with sync_playwright() as p:
        # Abrir navegador invisible simulando sistema de escritorio real
        browser = p.chromium.launch(headless=True)
        context = browser.new_context(
            user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
        )
        page = context.new_page()
        
        # 1. Navegación a la Portada Principal
        try:
            page.goto(BASE_URL, timeout=40000)
            page.wait_for_load_state("networkidle") # Espera a que cargue todo el contenido
            html_principal = page.content()
        except Exception as e:
            print(f"[ERROR] No se pudo acceder a la página de anime: {e}")
            browser.close()
            return

        soup = BeautifulSoup(html_principal, "lxml")
        
        # Localiza el encabezado de novedades
        encabezado = soup.find(string=re.compile(r"Recientemente Actualizado", re.IGNORECASE))
        if not encabezado:
            print("[AVISO] No se detectó la sección de novedades en la portada.")
            browser.close()
            return
            
        contenedor = encabezado.parent.parent.parent.parent
        enlaces_capitulos = contenedor.find_all("a", href=re.compile(r"/ver/"))
        
        episodios_detectados = []
        vistos = set()
        
        # 2. Navegación Interna por Capítulo
        for enlace in enlaces_capitulos:
            href = enlace.get("href", "")
            url_completa = href if href.startswith("http") else BASE_URL + href
            
            if url_completa in vistos:
                continue
            vistos.add(url_completa)
            
            titulo = enlace.get("title", "").strip()
            img_tag = enlace.find("img")
            imagen_url = img_tag.get("src") or img_tag.get("data-src") if img_tag else None
            
            if not titulo and img_tag:
                titulo = img_tag.get("alt", "").strip()
            if not titulo:
                titulo = enlace.get_text(strip=True)
                
            titulo_limpio = re.sub(r"^Ver\s+", "", titulo, flags=re.IGNORECASE)
            titulo_limpio = re.sub(r"\s+\d+$", "", titulo_limpio).strip()
            numero_episodio = _extraer_numero_episodio(enlace.get_text(" ", strip=True), url_completa)
            
            # Entrar a la página interna para recolectar iframes
            print(f"[PROCESANDO] Extrayendo servidores de video de: {titulo_limpio}...")
            try:
                page.goto(url_completa, timeout=25000)
                page.wait_for_load_state("domcontentloaded")
                html_interno = page.content()
                videos = extraer_reproductores_reales(html_interno)
            except Exception:
                videos = []
            
            episodios_detectados.append(
                EpisodioReciente(
                    id_slug=generar_id_desde_url(url_completa),
                    titulo=titulo_limpio,
                    episodio=numero_episodio,
                    imagen_url=imagen_url,
                    capitulo_url=url_completa,
                    links_referencia=videos
                )
            )
            time.sleep(1) # Pausa de seguridad anti-bloqueo
            
        browser.close()
        
        # 3. Guardar los datos recolectados en Firebase
        if episodios_detectados:
            db = inicializar_firestore(SERVICE_ACCOUNT_KEY_PATH)
            subir_a_firestore(db, episodios_detectados)
        else:
            print("[INFO] No se hallaron capítulos nuevos para poblar la base de datos.")

if __name__ == "__main__":
    ejecutar_extractor()
